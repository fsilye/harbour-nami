#ifndef FACEIMAGEPROVIDER_H
#define FACEIMAGEPROVIDER_H

#include <QQuickImageProvider>
#include <QString>

/**
 * @brief QML image provider serving cropped face thumbnails
 *
 * URL format:
 *   image://faces/crop?path=<url-encoded photo path>
 *                     &x=<bbox x>&y=<bbox y>&w=<bbox w>&h=<bbox h>
 *                     [&round=1]
 *
 * Bbox values are normalized (0-1) relative to the EXIF-oriented image,
 * as stored in the faces table. The crop is a square centered on the face
 * with margin around the bbox, cached on disk; `round=1` masks the result
 * to a circle (for avatars).
 *
 * requestImage runs on the QML image loader thread and only touches
 * files/QImage, never the database.
 */
class FaceImageProvider : public QQuickImageProvider
{
public:
    explicit FaceImageProvider(const QString &cacheDir);

    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;

private:
    QString m_cacheDir;

    // Master crop size cached on disk; requests are scaled down from it
    static const int kMasterSize = 512;

    // Extra margin around the detection bbox, as a fraction of its size
    // (YuNet boxes are tight; without margin crops cut hair/chin)
    static constexpr qreal kMargin = 0.45;
};

#endif // FACEIMAGEPROVIDER_H
