#ifdef QT_QML_DEBUG
#include <QtQuick>
#endif

#include <QGuiApplication>
#include <QQuickView>
#include <QQmlContext>
#include <QQmlEngine>
#include <QStandardPaths>
#include <QDir>
#include <QCoreApplication>
#include <QTranslator>
#include <QLocale>

#include "facepipeline.h"
#include "facedetector.h"
#include "facerecognizer.h"
#include "facedatabase.h"
#include "faceimageprovider.h"

int main(int argc, char *argv[])
{
    // Setup application
    QScopedPointer<QGuiApplication> app(new QGuiApplication(argc, argv));
    app->setApplicationName("harbour-nami");
    app->setOrganizationName("harbour-nami");

    // Create QML view
    QScopedPointer<QQuickView> view(new QQuickView);

    // Get application data paths
    QString dataDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QString cacheDir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    QString picturesDir = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation);

    // Create directories if needed
    QDir().mkpath(dataDir);
    QDir().mkpath(cacheDir);

    // Model paths (bundled with app)
    QString appDir = QCoreApplication::applicationDirPath() + "/../share/harbour-nami";

    // Load translations (falls back to source English strings)
    QTranslator *translator = new QTranslator(app.data());
    QString locale = QLocale::system().name();  // e.g. "fr_FR"
    QString i18nDir = appDir + "/translations";
    if (translator->load("harbour-nami-" + locale, i18nDir) ||
        translator->load("harbour-nami-" + locale.section('_', 0, 0), i18nDir)) {
        app->installTranslator(translator);
        qDebug() << "Loaded translation for" << locale;
    }
    QString detectorModelPath = appDir + "/models/face_detection_yunet_2023mar.onnx";
    QString recognizerModelPath = appDir + "/models/face_recognition_sface_2021dec.onnx";
    QString databasePath = dataDir + "/nami.db";

    qDebug() << "=== Harbour Nami Face Recognition ===";
    qDebug() << "Application directory:" << appDir;
    qDebug() << "Data directory:" << dataDir;
    qDebug() << "Cache directory:" << cacheDir;
    qDebug() << "Pictures directory:" << picturesDir;
    qDebug() << "Detector model:" << detectorModelPath;
    qDebug() << "Recognizer model:" << recognizerModelPath;
    qDebug() << "Database:" << databasePath;

    // Create face pipeline
    FacePipeline *pipeline = new FacePipeline(app.data());

    // Initialize pipeline
    bool initialized = pipeline->initialize(
        detectorModelPath,
        recognizerModelPath,
        databasePath
    );

    if (!initialized) {
        qCritical() << "Failed to initialize face pipeline!";
        qCritical() << "Make sure ML models are present in:" << appDir + "/models/";
        // Continue anyway - QML will show error page
    }

    // Face thumbnail provider (crops cached in the app cache dir)
    view->engine()->addImageProvider("faces", new FaceImageProvider(cacheDir));

    // Expose to QML
    view->rootContext()->setContextProperty("facePipeline", pipeline);
    view->rootContext()->setContextProperty("appDataDir", dataDir);
    view->rootContext()->setContextProperty("appCacheDir", cacheDir);
    view->rootContext()->setContextProperty("defaultGalleryPath", picturesDir);
#ifdef APP_VERSION
    view->rootContext()->setContextProperty("appVersion", QStringLiteral(APP_VERSION));
#else
    view->rootContext()->setContextProperty("appVersion", QStringLiteral("dev"));
#endif

    // Set QML source
    view->setSource(QUrl::fromLocalFile(appDir + "/qml/harbour-nami.qml"));

    // Show view
    view->showFullScreen();

    return app->exec();
}
