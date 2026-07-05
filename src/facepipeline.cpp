#include "facepipeline.h"
#include <QDebug>
#include "logging.h"
#include <QDir>
#include <QImageReader>
#include <QFile>
#include <QFileInfo>
#include <QtConcurrent>
#include <QSet>
#include <QStandardPaths>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>

FacePipeline::FacePipeline(QObject *parent)
    : QObject(parent)
    , m_detector(nullptr)
    , m_recognizer(nullptr)
    , m_database(nullptr)
    , m_initialized(false)
    , m_processing(false)
    , m_cancelRequested(false)
    , m_needsRescan(false)
    , m_currentScanIsForced(false)
    , m_totalPhotos(0)
    , m_processedPhotos(0)
    , m_personProtoCacheValid(false)
{
    connect(&m_extractionWatcher, &QFutureWatcher<PhotoExtraction>::finished,
            this, &FacePipeline::onExtractionFinished);
}

FacePipeline::~FacePipeline()
{
    // The worker uses m_detector/m_recognizer; let it finish first
    if (m_extractionWatcher.isRunning()) {
        m_extractionWatcher.waitForFinished();
    }

    delete m_detector;
    delete m_recognizer;
    delete m_database;
}

bool FacePipeline::initialize(const QString &detectorModelPath,
                              const QString &recognizerModelPath,
                              const QString &databasePath)
{
    qCDebug(lcNami) << "Initializing face pipeline...";
    qCDebug(lcNami) << "  Detector model:" << detectorModelPath;
    qCDebug(lcNami) << "  Recognizer model:" << recognizerModelPath;
    qCDebug(lcNami) << "  Database:" << databasePath;

    // Create detector
    m_detector = new FaceDetector(this);
    if (!m_detector->loadModel(detectorModelPath)) {
        emit error("Failed to load face detector model");
        return false;
    }

    // Create recognizer
    m_recognizer = new FaceRecognizer(this);
    if (!m_recognizer->loadModel(recognizerModelPath)) {
        emit error("Failed to load face recognizer model");
        return false;
    }

    // Create database
    m_database = new FaceDatabase(this);
    if (!m_database->open(databasePath)) {
        emit error("Failed to open database");
        return false;
    }

    // Embeddings computed by older engine versions are incompatible with
    // the current matching (different alignment/preprocessing)
    int storedVersion = m_database->getSetting("embedding_version", "1").toInt();
    m_needsRescan = (storedVersion != EMBEDDING_VERSION);
    if (m_needsRescan) {
        qWarning() << "Stored embeddings use version" << storedVersion
                   << "but engine is version" << EMBEDDING_VERSION
                   << "- a full re-scan is required";
        emit needsRescanChanged();
    }

    m_initialized = true;
    emit initializedChanged();

    qCDebug(lcNami) << "Face pipeline initialized successfully";
    return true;
}

void FacePipeline::scanGallery(const QString &galleryPath, bool recursive, bool forceRescan)
{
    if (!m_initialized) {
        emit error("Pipeline not initialized");
        return;
    }

    if (m_processing) {
        emit error("Already processing");
        return;
    }

    // Outdated embeddings: wipe face data so old and new embeddings are
    // never mixed, then re-process everything
    if (m_needsRescan) {
        qWarning() << "Clearing face data computed with an outdated engine version";
        m_database->clearFaceData();
        invalidatePersonPrototypes();
        forceRescan = true;
    }

    m_processing = true;
    m_cancelRequested = false;
    m_currentScanIsForced = forceRescan;
    emit processingChanged();

    qCDebug(lcNami) << "Scanning gallery:" << galleryPath << "(recursive:" << recursive
             << "force:" << forceRescan << ")";

    // Find all image files
    m_pendingFiles = findImageFiles(galleryPath, recursive);

    // Incremental scan: skip photos already processed
    if (!forceRescan) {
        QSet<QString> processedPaths = m_database->getProcessedFilePaths();
        if (!processedPaths.isEmpty()) {
            QStringList newFiles;
            for (const QString &file : m_pendingFiles) {
                if (!processedPaths.contains(file)) {
                    newFiles.append(file);
                }
            }
            qCDebug(lcNami) << "Incremental scan:" << (m_pendingFiles.size() - newFiles.size())
                     << "photos already processed," << newFiles.size() << "to process";
            m_pendingFiles = newFiles;
        }
    }

    m_totalPhotos = m_pendingFiles.size();
    m_processedPhotos = 0;
    m_totalFacesDetected = 0;

    emit totalPhotosChanged();
    emit scanStarted(m_totalPhotos);

    qCDebug(lcNami) << "Found" << m_totalPhotos << "image files";

    processNextPhoto();
}

void FacePipeline::processNextPhoto()
{
    if (m_cancelRequested) {
        finishScan(true);
        return;
    }

    if (m_pendingFiles.isEmpty()) {
        finishScan(false);
        return;
    }

    QString filePath = m_pendingFiles.takeFirst();
    emit scanProgress(m_processedPhotos + 1, m_totalPhotos, filePath);

    // Decode + detect + embed on a worker thread; the UI thread only does
    // the DB commit in onExtractionFinished
    m_extractionWatcher.setFuture(
        QtConcurrent::run(this, &FacePipeline::extractPhotoData, filePath));
}

void FacePipeline::onExtractionFinished()
{
    if (!m_processing) {
        return;
    }

    PhotoProcessingResult result = commitExtraction(m_extractionWatcher.result(),
                                                    m_currentScanIsForced);

    if (result.success) {
        m_totalFacesDetected += result.facesDetected;
    }

    emit photoProcessed(result);

    m_processedPhotos++;
    emit processedPhotosChanged();

    processNextPhoto();
}

void FacePipeline::finishScan(bool cancelled)
{
    m_processing = false;
    emit processingChanged();

    if (cancelled) {
        qCDebug(lcNami) << "Scan cancelled by user";
        emit scanFailed("Cancelled by user");
        return;
    }

    // Stored embeddings now match the engine
    m_database->setSetting("embedding_version", QString::number(EMBEDDING_VERSION));
    if (m_needsRescan) {
        m_needsRescan = false;
        emit needsRescanChanged();
    }

    emit scanCompleted(m_processedPhotos, m_totalFacesDetected);
    qCDebug(lcNami) << "Scan completed:" << m_processedPhotos << "photos," << m_totalFacesDetected << "faces";
}

PhotoProcessingResult FacePipeline::processPhoto(const QString &photoPath)
{
    if (!m_initialized) {
        return PhotoProcessingResult{-1, photoPath, 0, 0, false, "Pipeline not initialized"};
    }

    return commitExtraction(extractPhotoData(photoPath), false);
}

PhotoExtraction FacePipeline::extractPhotoData(const QString &photoPath)
{
    PhotoExtraction extraction;
    extraction.filePath = photoPath;
    extraction.loaded = false;
    extraction.width = 0;
    extraction.height = 0;

    qCDebug(lcNami) << "Processing photo:" << photoPath;

    QImage image = loadImage(photoPath);
    if (image.isNull()) {
        return extraction;
    }

    extraction.loaded = true;
    extraction.width = image.width();
    extraction.height = image.height();

    QFileInfo fileInfo(photoPath);
    extraction.dateTaken = fileInfo.lastModified();  // Could use EXIF data

    QVector<FaceDetection> detections = m_detector->detect(image);
    qCDebug(lcNami) << "Detected" << detections.size() << "faces";

    if (detections.isEmpty()) {
        return extraction;
    }

    // Convert once for all faces of this photo
    cv::Mat cvImage = m_detector->qImageToCvMat(image);

    for (const FaceDetection &detection : detections) {
        // Alignment to the 112x112 template happens inside the recognizer
        // (FaceRecognizerSF::alignCrop) using the detected landmarks
        FaceEmbedding embedding = m_recognizer->extractEmbedding(cvImage, detection);
        if (embedding.empty()) {
            qWarning() << "Failed to extract embedding for a face in" << photoPath;
            continue;
        }

        ExtractedFace face;
        face.bbox = detection.bbox;
        face.confidence = detection.confidence;
        face.embedding = embedding;
        extraction.faces.append(face);
    }

    return extraction;
}

PhotoProcessingResult FacePipeline::commitExtraction(const PhotoExtraction &extraction,
                                                     bool reprocess)
{
    PhotoProcessingResult result;
    result.photoId = -1;
    result.filePath = extraction.filePath;
    result.facesDetected = 0;
    result.facesMatched = 0;
    result.success = false;

    if (!extraction.loaded) {
        qWarning() << "Failed to load image:" << extraction.filePath;
        result.errorMessage = "Failed to load image";
        return result;
    }

    // All writes for one photo in a single transaction
    m_database->beginTransaction();

    int photoId = m_database->addPhoto(extraction.filePath, extraction.dateTaken,
                                       extraction.width, extraction.height);
    if (photoId < 0) {
        m_database->rollbackTransaction();
        result.errorMessage = "Failed to add photo to database";
        return result;
    }

    result.photoId = photoId;

    // The photo may already have faces from a previous scan; remove them
    // before re-adding, otherwise every scan duplicates all faces and
    // identified people keep reappearing as unknown
    if (reprocess) {
        m_database->deleteFacesForPhoto(photoId);
    } else if (m_database->getPhoto(photoId).processedAt.isValid()) {
        qCDebug(lcNami) << "Photo already processed, skipping:" << extraction.filePath;
        m_database->rollbackTransaction();
        result.success = true;
        return result;
    }

    result.facesDetected = extraction.faces.size();

    for (const ExtractedFace &face : extraction.faces) {
        FaceMatch match = matchFaceToDatabase(face.embedding);

        if (match.personId >= 0) {
            result.facesMatched++;
            qCDebug(lcNami) << "Matched face to person" << match.personId
                            << "with similarity" << match.similarity;
        }

        int faceId = m_database->addFace(photoId, face.bbox, face.confidence,
                                         face.embedding, match.personId,
                                         match.similarity, false);
        if (faceId < 0) {
            qWarning() << "Failed to add face to database for" << extraction.filePath;
        }
    }

    m_database->markPhotoProcessed(photoId);
    m_database->commitTransaction();

    result.success = true;
    return result;
}

int FacePipeline::groupUnknownFaces(float similarityThreshold)
{
    if (!m_initialized) {
        emit error("Pipeline not initialized");
        return 0;
    }

    qCDebug(lcNami) << "Grouping unknown faces with threshold:" << similarityThreshold;

    QVector<Face> unmappedFaces = m_database->getUnmappedFaces();
    qCDebug(lcNami) << "Found" << unmappedFaces.size() << "unmapped faces";

    if (unmappedFaces.isEmpty()) {
        return 0;
    }

    // Simple clustering by similarity
    int groupsCreated = 0;
    QVector<bool> processed(unmappedFaces.size(), false);

    for (int i = 0; i < unmappedFaces.size(); i++) {
        if (processed[i]) {
            continue;
        }

        // Create new person for this group
        QString groupName = QString("Person %1").arg(groupsCreated + 1);
        int personId = m_database->createPerson(groupName);

        if (personId < 0) {
            continue;
        }

        // Assign this face to the new person
        m_database->updateFacePersonMapping(unmappedFaces[i].id, personId);
        processed[i] = true;

        // Find similar faces
        for (int j = i + 1; j < unmappedFaces.size(); j++) {
            if (processed[j]) {
                continue;
            }

            float similarity = FaceRecognizer::computeSimilarity(
                unmappedFaces[i].embedding,
                unmappedFaces[j].embedding
            );

            if (similarity >= similarityThreshold) {
                m_database->updateFacePersonMapping(unmappedFaces[j].id, personId);
                processed[j] = true;
            }
        }

        groupsCreated++;
    }

    qCDebug(lcNami) << "Created" << groupsCreated << "groups";
    invalidatePersonPrototypes();
    return groupsCreated;
}

bool FacePipeline::identifyFace(int faceId, int personId, const QString &personName)
{
    if (!m_initialized) {
        emit error("Pipeline not initialized");
        return false;
    }

    // Create new person if needed
    if (personId < 0 && !personName.isEmpty()) {
        personId = m_database->createPerson(personName);
        if (personId < 0) {
            emit error("Failed to create person");
            return false;
        }
    }

    // Update face mapping
    if (!m_database->updateFacePersonMapping(faceId, personId)) {
        return false;
    }

    // Mark as verified (manually identified by user)
    if (!m_database->updateFaceMetadata(faceId, 1.0f, true)) {
        return false;
    }

    // Verified faces define the person prototype
    invalidatePersonPrototypes();

    // Automatic re-matching: After identifying a face, re-match unmapped faces
    // against the updated person profile
    qCDebug(lcNami) << "Re-matching unmapped faces against person" << personId;

    // Prototype built from user-verified faces (see getAverageEmbedding)
    FaceEmbedding personEmbedding = m_database->getAverageEmbedding(personId);
    if (personEmbedding.empty()) {
        qCDebug(lcNami) << "Could not get average embedding for person" << personId;
        return true;  // Still return success, re-matching is optional
    }

    // Get all unmapped faces (excludes ignored ones)
    QVector<Face> unmappedFaces = m_database->getUnmappedFaces();
    qCDebug(lcNami) << "Found" << unmappedFaces.size() << "unmapped faces to check";

    // Match each unmapped face against the person
    int autoMatched = 0;
    for (const Face &face : unmappedFaces) {
        // Respect user corrections: never reassign a rejected face
        if (m_database->hasNegativeMatch(face.id, personId)) {
            continue;
        }

        float similarity = FaceRecognizer::computeSimilarity(face.embedding, personEmbedding);

        // If similarity is above threshold, auto-assign to this person
        if (similarity >= AUTO_MATCH_THRESHOLD) {
            qCDebug(lcNami) << "Auto-matching face" << face.id << "to person" << personId
                     << "with similarity" << similarity;

            // Update face mapping with similarity score and verified=false (auto-matched)
            if (m_database->updateFacePersonMapping(face.id, personId)) {
                m_database->updateFaceMetadata(face.id, similarity, false);
                autoMatched++;
            }
        }
    }

    qCDebug(lcNami) << "Auto-matched" << autoMatched << "faces to person" << personId;

    return true;
}

void FacePipeline::cancel()
{
    m_cancelRequested = true;
}

// === Helpers ===

QStringList FacePipeline::findImageFiles(const QString &directory, bool recursive)
{
    QStringList imageFiles;
    QDir dir(directory);

    // Supported image formats
    QStringList nameFilters;
    nameFilters << "*.jpg" << "*.jpeg" << "*.png" << "*.bmp" << "*.gif";

    QDir::Filters filters = QDir::Files | QDir::Readable;
    if (recursive) {
        filters |= QDir::AllDirs | QDir::NoDotAndDotDot;
    }

    QFileInfoList entries = dir.entryInfoList(nameFilters, filters);

    for (const QFileInfo &entry : entries) {
        if (entry.isDir() && recursive) {
            imageFiles.append(findImageFiles(entry.absoluteFilePath(), true));
        } else if (entry.isFile()) {
            imageFiles.append(entry.absoluteFilePath());
        }
    }

    return imageFiles;
}

QImage FacePipeline::loadImage(const QString &filePath)
{
    QImageReader reader(filePath);
    reader.setAutoTransform(true);  // Handle EXIF orientation

    QImage image = reader.read();

    if (image.isNull()) {
        qWarning() << "Failed to load image:" << filePath << "-" << reader.errorString();
    }

    return image;
}

FaceMatch FacePipeline::matchFaceToDatabase(const FaceEmbedding &embedding, float threshold)
{
    const QVector<QPair<int, FaceEmbedding>> &prototypes = personPrototypes();

    if (prototypes.isEmpty()) {
        return FaceMatch{-1, 0.0f};  // No people in database yet
    }

    return FaceRecognizer::matchFace(embedding, prototypes, threshold);
}

const QVector<QPair<int, FaceEmbedding>> &FacePipeline::personPrototypes()
{
    // Prototypes only change when verified faces or people change
    // (identify, remove, merge, delete); unverified auto-assigns during a
    // scan don't affect them, so the cache stays valid for a whole scan
    if (!m_personProtoCacheValid) {
        m_personProtoCache = m_database->getAllPersonEmbeddings();
        m_personProtoCacheValid = true;
        qCDebug(lcNami) << "Person prototype cache rebuilt:" << m_personProtoCache.size() << "people";
    }

    return m_personProtoCache;
}

void FacePipeline::invalidatePersonPrototypes()
{
    m_personProtoCacheValid = false;
}

QVariantList FacePipeline::getAllPeople()
{
    QVariantList result;

    if (!m_initialized || !m_database) {
        return result;
    }

    QVector<Person> people = m_database->getAllPeople();

    for (const Person &person : people) {
        QVariantMap personMap;
        personMap["person_id"] = person.id;
        personMap["name"] = person.name;
        personMap["photo_count"] = person.photoCount;
        personMap["created_at"] = person.createdAt;
        result.append(personMap);
    }

    return result;
}

QVariantList FacePipeline::getPersonPhotos(int personId)
{
    QVariantList result;

    if (!m_initialized || !m_database) {
        return result;
    }

    // Get all faces for this person
    QVector<Face> faces = m_database->getFacesForPerson(personId);

    // Group faces by photo ID to get the best match per photo
    QMap<int, Face> bestFacePerPhoto;
    for (const Face &face : faces) {
        if (!bestFacePerPhoto.contains(face.photoId) ||
            face.similarityScore > bestFacePerPhoto[face.photoId].similarityScore) {
            bestFacePerPhoto[face.photoId] = face;
        }
    }

    // Get photo paths with face metadata
    for (const Face &face : bestFacePerPhoto.values()) {
        Photo photo = m_database->getPhoto(face.photoId);
        if (!photo.filePath.isEmpty()) {
            QVariantMap photoMap;
            photoMap["photo_id"] = photo.id;
            photoMap["face_id"] = face.id;
            photoMap["file_path"] = photo.filePath;
            photoMap["date_taken"] = photo.dateTaken;
            // Unix epoch seconds; Events/Memories group photos by this
            photoMap["timestamp"] = photo.dateTaken.isValid()
                ? photo.dateTaken.toMSecsSinceEpoch() / 1000 : 0;
            photoMap["similarity_score"] = face.similarityScore;
            photoMap["verified"] = face.verified;
            photoMap["bbox_x"] = face.bbox.x();
            photoMap["bbox_y"] = face.bbox.y();
            photoMap["bbox_width"] = face.bbox.width();
            photoMap["bbox_height"] = face.bbox.height();
            result.append(photoMap);
        }
    }

    return result;
}

QVariantMap FacePipeline::getPersonBestFace(int personId)
{
    QVariantMap result;

    if (!m_initialized || !m_database) {
        return result;
    }

    Face face = m_database->getBestFaceForPerson(personId);
    if (face.id < 0) {
        return result;
    }

    Photo photo = m_database->getPhoto(face.photoId);
    if (photo.filePath.isEmpty()) {
        return result;
    }

    result["face_id"] = face.id;
    result["photo_path"] = photo.filePath;
    result["bbox_x"] = face.bbox.x();
    result["bbox_y"] = face.bbox.y();
    result["bbox_width"] = face.bbox.width();
    result["bbox_height"] = face.bbox.height();

    return result;
}

bool FacePipeline::deletePerson(int personId)
{
    if (!m_initialized || !m_database) {
        return false;
    }

    invalidatePersonPrototypes();
    return m_database->deletePerson(personId);
}

bool FacePipeline::updatePersonName(int personId, const QString &name)
{
    if (!m_initialized || !m_database) {
        return false;
    }

    return m_database->updatePersonName(personId, name);
}

bool FacePipeline::mergePersons(int fromPersonId, int intoPersonId)
{
    if (!m_initialized || !m_database) {
        return false;
    }

    if (fromPersonId == intoPersonId || fromPersonId < 0 || intoPersonId < 0) {
        return false;
    }

    invalidatePersonPrototypes();
    return m_database->mergePersons(fromPersonId, intoPersonId);
}

bool FacePipeline::removeFaceFromPerson(int faceId)
{
    if (!m_initialized || !m_database) {
        return false;
    }

    // Remember the rejection, otherwise the next auto-match run reassigns
    // the face to the same person and the correction is lost
    Face face = m_database->getFace(faceId);
    if (face.personId >= 0) {
        m_database->addNegativeMatch(faceId, face.personId);
    }

    invalidatePersonPrototypes();
    return m_database->removeFaceFromPerson(faceId);
}

bool FacePipeline::ignoreFace(int faceId)
{
    if (!m_initialized || !m_database) {
        return false;
    }

    return m_database->setFaceIgnored(faceId, true);
}

QVariantList FacePipeline::getUnmappedFaces()
{
    QVariantList result;

    if (!m_initialized || !m_database) {
        return result;
    }

    QVector<Face> faces = m_database->getUnmappedFaces();

    for (const Face &face : faces) {
        Photo photo = m_database->getPhoto(face.photoId);

        QVariantMap faceMap;
        faceMap["face_id"] = face.id;
        faceMap["photo_id"] = face.photoId;
        faceMap["photo_path"] = photo.filePath;
        faceMap["bbox_x"] = face.bbox.x();
        faceMap["bbox_y"] = face.bbox.y();
        faceMap["bbox_width"] = face.bbox.width();
        faceMap["bbox_height"] = face.bbox.height();
        faceMap["confidence"] = face.confidence;
        result.append(faceMap);
    }

    return result;
}

QVariantMap FacePipeline::getStatistics()
{
    QVariantMap stats;

    if (!m_initialized || !m_database) {
        stats["total_photos"] = 0;
        stats["total_faces"] = 0;
        stats["total_people"] = 0;
        stats["db_size_bytes"] = 0;
        return stats;
    }

    return m_database->getStatistics();
}

bool FacePipeline::deleteAllData()
{
    if (!m_initialized || !m_database) {
        return false;
    }

    invalidatePersonPrototypes();

    // Face crops cached by the image provider are derived biometric data
    QString cacheDir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    QDir(cacheDir + "/faces").removeRecursively();

    return m_database->deleteAllData();
}

QString FacePipeline::exportData()
{
    if (!m_initialized || !m_database) {
        return QString();
    }

    QJsonObject root;
    root["app"] = "harbour-nami";
    root["exported_at"] = QDateTime::currentDateTime().toString(Qt::ISODate);
    root["statistics"] = QJsonObject::fromVariantMap(m_database->getStatistics());

    // Raw embeddings are deliberately not exported: they are biometric
    // templates with no human-readable value
    QJsonArray peopleArray;
    for (const Person &person : m_database->getAllPeople()) {
        QJsonObject personObj;
        personObj["id"] = person.id;
        personObj["name"] = person.name;
        personObj["created_at"] = person.createdAt.toString(Qt::ISODate);

        QJsonArray facesArray;
        for (const Face &face : m_database->getFacesForPerson(person.id)) {
            QJsonObject faceObj;
            faceObj["photo_path"] = m_database->getPhoto(face.photoId).filePath;
            faceObj["confidence"] = face.confidence;
            faceObj["similarity_score"] = face.similarityScore;
            faceObj["verified"] = face.verified;
            faceObj["detected_at"] = face.detectedAt.toString(Qt::ISODate);
            facesArray.append(faceObj);
        }
        personObj["faces"] = facesArray;

        peopleArray.append(personObj);
    }
    root["people"] = peopleArray;

    QString dir = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    QString filePath = dir + "/nami-export-"
        + QDateTime::currentDateTime().toString("yyyyMMdd-hhmmss") + ".json";

    QFile file(filePath);
    if (!file.open(QIODevice::WriteOnly)) {
        emit error("Failed to write export file: " + filePath);
        return QString();
    }

    file.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    file.close();

    // Contains names and photo paths
    QFile::setPermissions(filePath, QFileDevice::ReadOwner | QFileDevice::WriteOwner);

    qCDebug(lcNami) << "Data exported to" << filePath;
    return filePath;
}
