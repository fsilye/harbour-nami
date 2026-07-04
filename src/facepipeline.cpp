#include "facepipeline.h"
#include <QDebug>
#include <QDir>
#include <QImageReader>
#include <QFileInfo>
#include <QtConcurrent>
#include <QSet>

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
{
}

FacePipeline::~FacePipeline()
{
    delete m_detector;
    delete m_recognizer;
    delete m_database;
}

bool FacePipeline::initialize(const QString &detectorModelPath,
                              const QString &recognizerModelPath,
                              const QString &databasePath)
{
    qDebug() << "Initializing face pipeline...";
    qDebug() << "  Detector model:" << detectorModelPath;
    qDebug() << "  Recognizer model:" << recognizerModelPath;
    qDebug() << "  Database:" << databasePath;

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

    qDebug() << "Face pipeline initialized successfully";
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
        forceRescan = true;
    }

    m_processing = true;
    m_cancelRequested = false;
    m_currentScanIsForced = forceRescan;
    emit processingChanged();

    qDebug() << "Scanning gallery:" << galleryPath << "(recursive:" << recursive
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
            qDebug() << "Incremental scan:" << (m_pendingFiles.size() - newFiles.size())
                     << "photos already processed," << newFiles.size() << "to process";
            m_pendingFiles = newFiles;
        }
    }

    m_totalPhotos = m_pendingFiles.size();
    m_processedPhotos = 0;
    m_totalFacesDetected = 0;

    emit totalPhotosChanged();
    emit scanStarted(m_totalPhotos);

    qDebug() << "Found" << m_totalPhotos << "image files";

    // Start batch processing with timer to keep UI responsive
    processBatch();
}

void FacePipeline::processBatch()
{
    const int BATCH_SIZE = 5;  // Process 5 photos per batch
    const int BATCH_DELAY_MS = 50;  // 50ms delay between batches to keep UI responsive

    if (m_cancelRequested) {
        qDebug() << "Scan cancelled by user";
        m_processing = false;
        emit processingChanged();
        emit scanFailed("Cancelled by user");
        return;
    }

    if (m_pendingFiles.isEmpty()) {
        // All photos processed; stored embeddings now match the engine
        m_database->setSetting("embedding_version", QString::number(EMBEDDING_VERSION));
        if (m_needsRescan) {
            m_needsRescan = false;
            emit needsRescanChanged();
        }

        m_processing = false;
        emit processingChanged();
        emit scanCompleted(m_processedPhotos, m_totalFacesDetected);
        qDebug() << "Scan completed:" << m_processedPhotos << "photos," << m_totalFacesDetected << "faces";
        return;
    }

    // Process a batch of photos
    int processed = 0;
    while (processed < BATCH_SIZE && !m_pendingFiles.isEmpty()) {
        QString filePath = m_pendingFiles.takeFirst();

        emit scanProgress(m_processedPhotos + 1, m_totalPhotos, filePath);

        PhotoProcessingResult result = processPhotoInternal(filePath, m_currentScanIsForced);

        if (result.success) {
            m_totalFacesDetected += result.facesDetected;
        }

        emit photoProcessed(result);

        m_processedPhotos++;
        emit processedPhotosChanged();

        processed++;
    }

    // Schedule next batch with a small delay to keep UI responsive
    QTimer::singleShot(BATCH_DELAY_MS, this, &FacePipeline::processBatch);
}

PhotoProcessingResult FacePipeline::processPhoto(const QString &photoPath)
{
    if (!m_initialized) {
        return PhotoProcessingResult{-1, photoPath, 0, 0, false, "Pipeline not initialized"};
    }

    return processPhotoInternal(photoPath);
}

PhotoProcessingResult FacePipeline::processPhotoInternal(const QString &photoPath, bool reprocess)
{
    PhotoProcessingResult result;
    result.filePath = photoPath;
    result.facesDetected = 0;
    result.facesMatched = 0;
    result.success = false;

    qDebug() << "";
    qDebug() << "╔═══════════════════════════════════════════════════════════════╗";
    qDebug() << "║ Processing photo:" << photoPath;
    qDebug() << "╚═══════════════════════════════════════════════════════════════╝";

    // Load image
    qDebug() << "→ Loading image...";
    QImage image = loadImage(photoPath);
    if (image.isNull()) {
        qWarning() << "✗ Failed to load image";
        result.errorMessage = "Failed to load image";
        return result;
    }
    qDebug() << "✓ Image loaded:" << image.width() << "x" << image.height() << "format:" << image.format();

    // Get or create photo record
    QFileInfo fileInfo(photoPath);
    QDateTime dateTaken = fileInfo.lastModified();  // Could use EXIF data

    qDebug() << "→ Adding photo to database...";
    int photoId = m_database->addPhoto(photoPath, dateTaken, image.width(), image.height());
    if (photoId < 0) {
        qWarning() << "✗ Failed to add photo to database";
        result.errorMessage = "Failed to add photo to database";
        return result;
    }
    qDebug() << "✓ Photo added to DB with ID:" << photoId;

    result.photoId = photoId;

    // The photo may already have faces from a previous scan; remove them
    // before re-detecting, otherwise every scan duplicates all faces and
    // identified people keep reappearing as unknown
    if (reprocess) {
        m_database->deleteFacesForPhoto(photoId);
    } else if (m_database->getPhoto(photoId).processedAt.isValid()) {
        qDebug() << "ℹ Photo already processed, skipping";
        result.success = true;
        return result;
    }

    // Detect faces
    qDebug() << "→ Starting face detection...";
    QVector<FaceDetection> detections = m_detector->detect(image);
    result.facesDetected = detections.size();

    qDebug() << "✓ Face detection complete:" << detections.size() << "faces found";

    if (detections.isEmpty()) {
        qDebug() << "⚠ No faces detected in this image";
    }

    // Convert once for all faces of this photo
    cv::Mat cvImage;
    if (!detections.isEmpty()) {
        cvImage = m_detector->qImageToCvMat(image);
    }

    // Process each detected face
    for (int i = 0; i < detections.size(); i++) {
        const FaceDetection &detection = detections[i];
        qDebug() << "  → Processing face" << (i+1) << "/" << detections.size()
                 << "- confidence:" << detection.confidence;

        // Align face to the ArcFace template using the detected landmarks
        cv::Mat faceRegion = alignFace(cvImage, detection);
        qDebug() << "    ✓ Face aligned:" << faceRegion.cols << "x" << faceRegion.rows;

        // Extract embedding
        qDebug() << "    → Extracting face embedding...";
        FaceEmbedding embedding = m_recognizer->extractEmbedding(faceRegion);

        if (embedding.empty()) {
            qWarning() << "    ✗ Failed to extract embedding for face";
            continue;
        }
        qDebug() << "    ✓ Embedding extracted (size:" << embedding.size() << ")";

        // Match against database
        qDebug() << "    → Matching against database...";
        FaceMatch match = matchFaceToDatabase(embedding);

        if (match.personId >= 0) {
            result.facesMatched++;
            qDebug() << "    ✓ Matched to person ID:" << match.personId
                     << "with similarity:" << match.similarity;
        } else {
            qDebug() << "    ○ No match found (new face)";
        }

        // Store in database with similarity score
        qDebug() << "    → Storing face in database...";
        int faceId = m_database->addFace(photoId, detection.bbox, detection.confidence,
                                         embedding, match.personId, match.similarity, false);

        if (faceId < 0) {
            qWarning() << "    ✗ Failed to add face to database";
        } else {
            qDebug() << "    ✓ Face stored with ID:" << faceId;
        }
    }

    // Mark photo as processed
    m_database->markPhotoProcessed(photoId);

    result.success = true;
    qDebug() << "═══════════════════════════════════════════════════════════════";
    qDebug() << "Photo processing summary:";
    qDebug() << "  Faces detected:" << result.facesDetected;
    qDebug() << "  Faces matched:" << result.facesMatched;
    qDebug() << "═══════════════════════════════════════════════════════════════";
    qDebug() << "";

    return result;
}

int FacePipeline::groupUnknownFaces(float similarityThreshold)
{
    if (!m_initialized) {
        emit error("Pipeline not initialized");
        return 0;
    }

    qDebug() << "Grouping unknown faces with threshold:" << similarityThreshold;

    QVector<Face> unmappedFaces = m_database->getUnmappedFaces();
    qDebug() << "Found" << unmappedFaces.size() << "unmapped faces";

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

    qDebug() << "Created" << groupsCreated << "groups";
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

    // Automatic re-matching: After identifying a face, re-match unmapped faces
    // against the updated person profile
    qDebug() << "Re-matching unmapped faces against person" << personId;

    // Prototype built from user-verified faces (see getAverageEmbedding)
    FaceEmbedding personEmbedding = m_database->getAverageEmbedding(personId);
    if (personEmbedding.empty()) {
        qDebug() << "Could not get average embedding for person" << personId;
        return true;  // Still return success, re-matching is optional
    }

    // Get all unmapped faces (excludes ignored ones)
    QVector<Face> unmappedFaces = m_database->getUnmappedFaces();
    qDebug() << "Found" << unmappedFaces.size() << "unmapped faces to check";

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
            qDebug() << "Auto-matching face" << face.id << "to person" << personId
                     << "with similarity" << similarity;

            // Update face mapping with similarity score and verified=false (auto-matched)
            if (m_database->updateFacePersonMapping(face.id, personId)) {
                m_database->updateFaceMetadata(face.id, similarity, false);
                autoMatched++;
            }
        }
    }

    qDebug() << "Auto-matched" << autoMatched << "faces to person" << personId;

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

cv::Mat FacePipeline::alignFace(const cv::Mat &image, const FaceDetection &detection)
{
    // Standard ArcFace 112x112 destination landmarks, same order as YuNet:
    // right eye, left eye, nose tip, right mouth corner, left mouth corner
    // ("right" = subject's right, i.e. image-left on an upright face)
    static const float kArcFaceTemplate[5][2] = {
        {38.2946f, 51.6963f},
        {73.5318f, 51.5014f},
        {56.0252f, 71.7366f},
        {41.5493f, 92.3655f},
        {70.7299f, 92.2041f}
    };

    if (detection.landmarks.size() == 5) {
        // Least-squares similarity transform (scale+rotation+translation)
        // mapping detected landmarks onto the template. Closed form to
        // avoid depending on calib3d (not bundled).
        double meanSrcX = 0, meanSrcY = 0, meanDstX = 0, meanDstY = 0;
        for (int i = 0; i < 5; i++) {
            meanSrcX += detection.landmarks[i].x() * image.cols;
            meanSrcY += detection.landmarks[i].y() * image.rows;
            meanDstX += kArcFaceTemplate[i][0];
            meanDstY += kArcFaceTemplate[i][1];
        }
        meanSrcX /= 5; meanSrcY /= 5; meanDstX /= 5; meanDstY /= 5;

        double num_a = 0, num_b = 0, denom = 0;
        for (int i = 0; i < 5; i++) {
            double sx = detection.landmarks[i].x() * image.cols - meanSrcX;
            double sy = detection.landmarks[i].y() * image.rows - meanSrcY;
            double dx = kArcFaceTemplate[i][0] - meanDstX;
            double dy = kArcFaceTemplate[i][1] - meanDstY;
            num_a += sx * dx + sy * dy;
            num_b += sx * dy - sy * dx;
            denom += sx * sx + sy * sy;
        }

        if (denom > 1e-6) {
            double a = num_a / denom;
            double b = num_b / denom;
            double tx = meanDstX - (a * meanSrcX - b * meanSrcY);
            double ty = meanDstY - (b * meanSrcX + a * meanSrcY);

            cv::Mat transform = (cv::Mat_<double>(2, 3) << a, -b, tx, b, a, ty);
            cv::Mat aligned;
            cv::warpAffine(image, aligned, transform, cv::Size(112, 112),
                           cv::INTER_LINEAR, cv::BORDER_REPLICATE);
            return aligned;
        }
    }

    // Fallback: bbox crop (degenerate landmarks or none)
    int x = static_cast<int>(detection.bbox.x() * image.cols);
    int y = static_cast<int>(detection.bbox.y() * image.rows);
    int w = static_cast<int>(detection.bbox.width() * image.cols);
    int h = static_cast<int>(detection.bbox.height() * image.rows);

    x = std::max(0, std::min(x, image.cols - 1));
    y = std::max(0, std::min(y, image.rows - 1));
    w = std::max(1, std::min(w, image.cols - x));
    h = std::max(1, std::min(h, image.rows - y));

    return image(cv::Rect(x, y, w, h)).clone();
}

FaceMatch FacePipeline::matchFaceToDatabase(const FaceEmbedding &embedding, float threshold)
{
    // Get all person embeddings
    QVector<QPair<int, FaceEmbedding>> personEmbeddings = m_database->getAllPersonEmbeddings();

    if (personEmbeddings.isEmpty()) {
        return FaceMatch{-1, 0.0f};  // No people in database yet
    }

    // Match against database
    FaceMatch match = FaceRecognizer::matchFace(embedding, personEmbeddings, threshold);

    if (match.personId >= 0) {
        qDebug() << "Matched face to person" << match.personId
                 << "with similarity" << match.similarity;
    }

    return match;
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
            photoMap["similarity_score"] = face.similarityScore;
            photoMap["verified"] = face.verified;
            result.append(photoMap);
        }
    }

    return result;
}

bool FacePipeline::deletePerson(int personId)
{
    if (!m_initialized || !m_database) {
        return false;
    }

    return m_database->deletePerson(personId);
}

bool FacePipeline::updatePersonName(int personId, const QString &name)
{
    if (!m_initialized || !m_database) {
        return false;
    }

    return m_database->updatePersonName(personId, name);
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

    return m_database->deleteAllData();
}
