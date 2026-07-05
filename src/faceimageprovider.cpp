#include "faceimageprovider.h"
#include "logging.h"

#include <QUrlQuery>
#include <QUrl>
#include <QImageReader>
#include <QFileInfo>
#include <QDir>
#include <QFile>
#include <QCryptographicHash>
#include <QPainter>
#include <QPainterPath>
#include <QDebug>

FaceImageProvider::FaceImageProvider(const QString &cacheDir)
    : QQuickImageProvider(QQuickImageProvider::Image)
    , m_cacheDir(cacheDir + "/faces")
{
    QDir().mkpath(m_cacheDir);
}

QImage FaceImageProvider::requestImage(const QString &id, QSize *size, const QSize &requestedSize)
{
    // id looks like "crop?path=...&x=...&y=...&w=...&h=...[&round=1]"
    int queryStart = id.indexOf('?');
    if (queryStart < 0) {
        qWarning() << "FaceImageProvider: malformed id" << id;
        return QImage();
    }

    QUrlQuery query(id.mid(queryStart + 1));
    QString path = query.queryItemValue("path", QUrl::FullyDecoded);
    qreal bx = query.queryItemValue("x").toDouble();
    qreal by = query.queryItemValue("y").toDouble();
    qreal bw = query.queryItemValue("w").toDouble();
    qreal bh = query.queryItemValue("h").toDouble();
    bool round = query.queryItemValue("round") == QLatin1String("1");

    QFileInfo fileInfo(path);
    if (!fileInfo.exists() || bw <= 0 || bh <= 0) {
        return QImage();
    }

    // Disk cache keyed on file identity and bbox
    QString cacheKey = QString("%1|%2|%3|%4|%5|%6")
        .arg(path).arg(fileInfo.lastModified().toMSecsSinceEpoch())
        .arg(bx).arg(by).arg(bw).arg(bh);
    QString cacheFile = m_cacheDir + "/"
        + QCryptographicHash::hash(cacheKey.toUtf8(), QCryptographicHash::Sha1).toHex()
        + ".jpg";

    QImage crop;
    if (QFile::exists(cacheFile)) {
        crop.load(cacheFile);
    }

    if (crop.isNull()) {
        QImageReader reader(path);
        reader.setAutoTransform(true);  // bbox was computed on the oriented image

        QImage image = reader.read();
        if (image.isNull()) {
            qWarning() << "FaceImageProvider: failed to load" << path;
            return QImage();
        }

        // Square crop centered on the face, bbox expanded by the margin
        qreal faceW = bw * image.width();
        qreal faceH = bh * image.height();
        qreal centerX = (bx + bw / 2.0) * image.width();
        qreal centerY = (by + bh / 2.0) * image.height();

        int side = static_cast<int>(qMax(faceW, faceH) * (1.0 + 2.0 * kMargin));
        side = qMin(side, qMin(image.width(), image.height()));
        side = qMax(side, 1);

        int cropX = static_cast<int>(centerX - side / 2.0);
        int cropY = static_cast<int>(centerY - side / 2.0);
        cropX = qBound(0, cropX, image.width() - side);
        cropY = qBound(0, cropY, image.height() - side);

        crop = image.copy(cropX, cropY, side, side);

        if (crop.width() > kMasterSize) {
            crop = crop.scaled(kMasterSize, kMasterSize,
                               Qt::KeepAspectRatio, Qt::SmoothTransformation);
        }

        crop.save(cacheFile, "JPG", 88);
        QFile::setPermissions(cacheFile, QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    }

    // Scale to the requested size
    QSize targetSize = requestedSize;
    if (!targetSize.isValid() || targetSize.width() <= 0 || targetSize.height() <= 0) {
        targetSize = crop.size();
    }
    QImage scaled = crop.scaled(targetSize, Qt::KeepAspectRatioByExpanding,
                                Qt::SmoothTransformation);

    // Circular mask for avatars (no QtGraphicalEffects dependency in QML)
    if (round) {
        QImage rounded(scaled.size(), QImage::Format_ARGB32_Premultiplied);
        rounded.fill(Qt::transparent);

        QPainter painter(&rounded);
        painter.setRenderHint(QPainter::Antialiasing);
        QPainterPath clip;
        clip.addEllipse(0, 0, scaled.width(), scaled.height());
        painter.setClipPath(clip);
        painter.drawImage(0, 0, scaled);
        painter.end();

        scaled = rounded;
    }

    if (size) {
        *size = scaled.size();
    }

    return scaled;
}
