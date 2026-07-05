#ifndef FACEPIPELINE_H
#define FACEPIPELINE_H

#include <QObject>
#include <QString>
#include <QImage>
#include <QVector>
#include <QFuture>
#include <QFutureWatcher>
#include "facedetector.h"
#include "facerecognizer.h"
#include "facedatabase.h"

/**
 * @brief Processing result for a single photo
 */
struct PhotoProcessingResult {
    int photoId;
    QString filePath;
    int facesDetected;
    int facesMatched;
    bool success;
    QString errorMessage;
};

/**
 * @brief One face extracted from a photo (detection + embedding, no DB state)
 */
struct ExtractedFace {
    QRectF bbox;
    float confidence;
    FaceEmbedding embedding;
};

/**
 * @brief CPU-heavy part of photo processing, computed on a worker thread.
 *
 * Deliberately contains no database identifiers: QSqlDatabase connections
 * are bound to the thread that created them, so all DB access stays on the
 * main thread while decoding/detection/embedding run in the background.
 */
struct PhotoExtraction {
    QString filePath;
    bool loaded;
    int width;
    int height;
    QDateTime dateTaken;
    QVector<ExtractedFace> faces;
};

/**
 * @brief Main face recognition pipeline
 *
 * Orchestrates the complete face recognition workflow:
 * 1. Gallery scanning
 * 2. Face detection (YuNet)
 * 3. Face recognition (ArcFace)
 * 4. Database storage
 * 5. Automatic face grouping
 */
class FacePipeline : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool initialized READ isInitialized NOTIFY initializedChanged)
    Q_PROPERTY(bool processing READ isProcessing NOTIFY processingChanged)
    Q_PROPERTY(int totalPhotos READ totalPhotos NOTIFY totalPhotosChanged)
    Q_PROPERTY(int processedPhotos READ processedPhotos NOTIFY processedPhotosChanged)
    Q_PROPERTY(bool needsRescan READ needsRescan NOTIFY needsRescanChanged)

public:
    // Bump when embedding computation changes (model, alignment,
    // preprocessing...); stored embeddings are then incompatible and a full
    // re-scan is forced
    static constexpr int EMBEDDING_VERSION = 3;

    // Thresholds on the rescaled similarity (cosine mapped from [-1,1] to
    // [0,1]). SFace's official same-identity cosine threshold is 0.363,
    // i.e. ~0.68 rescaled. Auto-assign must be stricter than interactive
    // suggestions: a silent wrong match poisons the person prototype.
    static constexpr float AUTO_MATCH_THRESHOLD = 0.72f;
    static constexpr float GROUPING_THRESHOLD = 0.68f;

    explicit FacePipeline(QObject *parent = nullptr);
    ~FacePipeline();

    /**
     * @brief Initialize the pipeline
     * @param detectorModelPath Path to YuNet model
     * @param recognizerModelPath Path to ArcFace model
     * @param databasePath Path to SQLite database
     * @return true if initialized successfully
     */
    Q_INVOKABLE bool initialize(const QString &detectorModelPath,
                                const QString &recognizerModelPath,
                                const QString &databasePath);

    /**
     * @brief Scan gallery and process photos
     *
     * Incremental by default: photos already processed are skipped. When
     * forceRescan is true (or stored embeddings are outdated), existing
     * faces are recomputed.
     *
     * @param galleryPath Path to gallery (e.g., ~/Pictures)
     * @param recursive Scan subdirectories
     * @param forceRescan Re-process photos already scanned
     */
    Q_INVOKABLE void scanGallery(const QString &galleryPath, bool recursive = true,
                                 bool forceRescan = false);

    /**
     * @brief Process a single photo
     * @param photoPath Path to photo file
     * @return Processing result
     */
    Q_INVOKABLE PhotoProcessingResult processPhoto(const QString &photoPath);

    /**
     * @brief Group unknown faces by similarity
     * @param similarityThreshold Threshold for grouping (default: 0.7)
     * @return Number of groups created
     */
    Q_INVOKABLE int groupUnknownFaces(float similarityThreshold = GROUPING_THRESHOLD);

    /**
     * @brief Identify a face as a person
     * @param faceId Face ID
     * @param personId Person ID (or -1 to create new person)
     * @param personName Name for new person (if personId == -1)
     */
    Q_INVOKABLE bool identifyFace(int faceId, int personId, const QString &personName = QString());

    /**
     * @brief Cancel current operation
     */
    Q_INVOKABLE void cancel();

    /**
     * @brief Get all people from database
     * @return List of people as QVariantList
     */
    Q_INVOKABLE QVariantList getAllPeople();

    /**
     * @brief Get photos for a specific person
     * @param personId Person ID
     * @return List of photo paths as QVariantList
     */
    Q_INVOKABLE QVariantList getPersonPhotos(int personId);

    /**
     * @brief Best face of a person for avatar display
     * @param personId Person ID
     * @return Map with face_id, photo_path and normalized bbox fields,
     *         empty map when the person has no faces
     */
    Q_INVOKABLE QVariantMap getPersonBestFace(int personId);

    /**
     * @brief Delete a person and unmap their faces
     * @param personId Person ID
     * @return true if successful
     */
    Q_INVOKABLE bool deletePerson(int personId);

    /**
     * @brief Update person's name
     * @param personId Person ID
     * @param name New name
     * @return true if successful
     */
    Q_INVOKABLE bool updatePersonName(int personId, const QString &name);

    /**
     * @brief Merge one person into another
     *
     * All faces of fromPersonId are reassigned to intoPersonId and
     * fromPersonId is deleted. Needed to converge when clustering created
     * duplicates of the same human.
     *
     * @param fromPersonId Person to dissolve
     * @param intoPersonId Person that receives the faces
     * @return true if successful
     */
    Q_INVOKABLE bool mergePersons(int fromPersonId, int intoPersonId);

    /**
     * @brief Get all unmapped faces
     * @return List of faces as QVariantList
     */
    Q_INVOKABLE QVariantList getUnmappedFaces();

    /**
     * @brief Remove face from person (unassign)
     *
     * Records a rejection so auto-matching never reassigns this face to
     * the same person.
     *
     * @param faceId Face ID to remove from person
     * @return true if successful
     */
    Q_INVOKABLE bool removeFaceFromPerson(int faceId);

    /**
     * @brief Permanently ignore a face (false positive, stranger, low quality)
     *
     * Ignored faces no longer appear in the identify flow or clustering.
     *
     * @param faceId Face ID to ignore
     * @return true if successful
     */
    Q_INVOKABLE bool ignoreFace(int faceId);

    /**
     * @brief Get database statistics
     * @return QVariantMap with stats (total_photos, total_faces, total_people, db_size_bytes)
     */
    Q_INVOKABLE QVariantMap getStatistics();

    /**
     * @brief Delete all face recognition data
     * @return true if successful
     */
    Q_INVOKABLE bool deleteAllData();

    /**
     * @brief Export all data to a JSON file (GDPR data portability)
     * @return Path of the written file, or empty string on failure
     */
    Q_INVOKABLE QString exportData();

    // === Property getters ===

    bool isInitialized() const { return m_initialized; }
    bool isProcessing() const { return m_processing; }
    int totalPhotos() const { return m_totalPhotos; }
    int processedPhotos() const { return m_processedPhotos; }
    bool needsRescan() const { return m_needsRescan; }

signals:
    void initializedChanged();
    void processingChanged();
    void totalPhotosChanged();
    void processedPhotosChanged();
    void needsRescanChanged();

    void scanStarted(int totalPhotos);
    void scanProgress(int current, int total, const QString &currentFile);
    void scanCompleted(int photosProcessed, int facesDetected);
    void scanFailed(const QString &error);

    void photoProcessed(const PhotoProcessingResult &result);

    void error(const QString &message);

private:
    FaceDetector *m_detector;
    FaceRecognizer *m_recognizer;
    FaceDatabase *m_database;

    bool m_initialized;
    bool m_processing;
    bool m_cancelRequested;
    bool m_needsRescan;
    bool m_currentScanIsForced;
    int m_totalPhotos;
    int m_processedPhotos;
    int m_totalFacesDetected;
    QStringList m_pendingFiles;

    // One photo in flight at a time: extraction runs on a worker thread,
    // DB commit happens back on the main thread (QSqlDatabase affinity)
    QFutureWatcher<PhotoExtraction> m_extractionWatcher;

    // Person prototypes cache; recomputing them from the DB for every
    // detected face is O(persons x faces) queries per photo
    QVector<QPair<int, FaceEmbedding>> m_personProtoCache;
    bool m_personProtoCacheValid;

    // Helper: Start extraction of the next pending photo (scan loop)
    void processNextPhoto();

    // Helper: Commit a finished extraction and continue the scan loop
    void onExtractionFinished();

    // Helper: Finish the scan (completed or cancelled)
    void finishScan(bool cancelled);

    // Helper: CPU-heavy part, safe to run on a worker thread (no DB)
    PhotoExtraction extractPhotoData(const QString &photoPath);

    // Helper: DB part, main thread only
    PhotoProcessingResult commitExtraction(const PhotoExtraction &extraction, bool reprocess);

    // Helper: Find image files in directory
    QStringList findImageFiles(const QString &directory, bool recursive);

    // Helper: Load and validate image
    QImage loadImage(const QString &filePath);

    // Helper: Match face against cached person prototypes
    FaceMatch matchFaceToDatabase(const FaceEmbedding &embedding,
                                  float threshold = AUTO_MATCH_THRESHOLD);

    // Helper: Person prototypes, cached
    const QVector<QPair<int, FaceEmbedding>> &personPrototypes();
    void invalidatePersonPrototypes();
};

#endif // FACEPIPELINE_H
