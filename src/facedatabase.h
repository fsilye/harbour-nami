#ifndef FACEDATABASE_H
#define FACEDATABASE_H

#include <QObject>
#include <QString>
#include <QVector>
#include <QSet>
#include <QVariantMap>
#include <QDateTime>
#include <QSqlDatabase>
#include "facerecognizer.h"

/**
 * @brief Photo record
 */
struct Photo {
    int id;
    QString filePath;
    QDateTime dateTaken;
    int width;
    int height;
    QDateTime processedAt;
};

/**
 * @brief Person record
 */
struct Person {
    int id;
    QString name;
    QDateTime createdAt;
    int photoCount;
};

/**
 * @brief Face record
 */
struct Face {
    int id;
    int photoId;
    QRectF bbox;
    float confidence;
    FaceEmbedding embedding;
    int personId;  // -1 if unmapped
    float similarityScore;  // Similarity score when matched (0.0-1.0)
    bool verified;  // true if manually verified by user
    QDateTime detectedAt;
};

/**
 * @brief SQLite database manager for faces and photos
 *
 * Manages:
 * - Photos metadata
 * - Face detections with embeddings
 * - People and face mappings
 * - GDPR compliance (export, deletion)
 */
class FaceDatabase : public QObject
{
    Q_OBJECT

public:
    explicit FaceDatabase(QObject *parent = nullptr);
    ~FaceDatabase();

    /**
     * @brief Open database connection
     * @param dbPath Path to SQLite database file
     * @return true if opened successfully
     */
    bool open(const QString &dbPath);

    /**
     * @brief Close database connection
     */
    void close();

    /**
     * @brief Initialize database schema
     * @return true if successful
     */
    bool initializeSchema();

    // === Transactions (batch several writes, e.g. one photo commit) ===

    bool beginTransaction();
    bool commitTransaction();
    bool rollbackTransaction();

    // === Photo operations ===

    /**
     * @brief Add photo to database
     * @return Photo ID or -1 on error
     */
    int addPhoto(const QString &filePath, const QDateTime &dateTaken,
                 int width, int height);

    /**
     * @brief Get photo by ID
     */
    Photo getPhoto(int photoId);

    /**
     * @brief Get all photos
     */
    QVector<Photo> getAllPhotos();

    /**
     * @brief Mark photo as processed
     */
    bool markPhotoProcessed(int photoId);

    // === Face operations ===

    /**
     * @brief Add face detection to database
     * @return Face ID or -1 on error
     */
    int addFace(int photoId, const QRectF &bbox, float confidence,
                const FaceEmbedding &embedding, int personId = -1,
                float similarityScore = 0.0f, bool verified = false);

    /**
     * @brief Get face by ID
     */
    Face getFace(int faceId);

    /**
     * @brief Get all faces for a photo
     */
    QVector<Face> getFacesForPhoto(int photoId);

    /**
     * @brief Get all unmapped faces (personId = -1)
     */
    QVector<Face> getUnmappedFaces();

    /**
     * @brief Update face's person mapping
     */
    bool updateFacePersonMapping(int faceId, int personId);

    /**
     * @brief Update face metadata (similarity score, verified status)
     */
    bool updateFaceMetadata(int faceId, float similarityScore, bool verified);

    /**
     * @brief Remove face from person (set person_id to -1)
     */
    bool removeFaceFromPerson(int faceId);

    /**
     * @brief Mark face as ignored (not a face / not worth identifying)
     */
    bool setFaceIgnored(int faceId, bool ignored);

    /**
     * @brief Record that a face must never be auto-matched to a person
     */
    bool addNegativeMatch(int faceId, int personId);

    /**
     * @brief Check if a face was rejected for a person
     */
    bool hasNegativeMatch(int faceId, int personId);

    /**
     * @brief Delete all faces of a photo (used when re-processing)
     */
    bool deleteFacesForPhoto(int photoId);

    /**
     * @brief File paths of photos already processed (for incremental scans)
     */
    QSet<QString> getProcessedFilePaths();

    // === Person operations ===

    /**
     * @brief Create new person
     * @return Person ID or -1 on error
     */
    int createPerson(const QString &name);

    /**
     * @brief Get person by ID
     */
    Person getPerson(int personId);

    /**
     * @brief Get all people
     */
    QVector<Person> getAllPeople();

    /**
     * @brief Update person name
     */
    bool updatePersonName(int personId, const QString &name);

    /**
     * @brief Delete person and unmap their faces
     */
    bool deletePerson(int personId);

    /**
     * @brief Merge fromPersonId into intoPersonId and delete fromPersonId
     *
     * Faces, verified flags and rejections carry over.
     */
    bool mergePersons(int fromPersonId, int intoPersonId);

    /**
     * @brief Get all faces for a person
     */
    QVector<Face> getFacesForPerson(int personId);

    /**
     * @brief Best face of a person for display (verified first, then
     *        highest similarity, then detection confidence)
     * @return Face with id -1 when the person has no faces
     */
    Face getBestFaceForPerson(int personId);

    /**
     * @brief Get average embedding for a person
     */
    FaceEmbedding getAverageEmbedding(int personId);

    /**
     * @brief Get all person embeddings for matching
     * @return Vector of (personId, averageEmbedding) pairs
     */
    QVector<QPair<int, FaceEmbedding>> getAllPersonEmbeddings();

    // === GDPR compliance ===

    /**
     * @brief Export all data for a person (GDPR right to data portability)
     */
    QVariantMap exportPersonData(int personId);

    /**
     * @brief Delete all data (GDPR right to be forgotten)
     */
    bool deleteAllData();

    /**
     * @brief Delete faces, people and rejections but keep photo records
     *
     * Used when the recognition engine changes and embeddings must be
     * recomputed. Photos are marked unprocessed.
     */
    bool clearFaceData();

    // === Settings ===

    /**
     * @brief Get a value from the settings table
     */
    QString getSetting(const QString &key, const QString &defaultValue = QString());

    /**
     * @brief Store a value in the settings table
     */
    bool setSetting(const QString &key, const QString &value);

    // === Statistics ===

    /**
     * @brief Get database statistics
     */
    QVariantMap getStatistics();

signals:
    void error(const QString &message);

private:
    QSqlDatabase m_db;
    QString m_dbPath;
    bool m_isOpen;

    // Helper: Serialize embedding to BLOB
    QByteArray serializeEmbedding(const FaceEmbedding &embedding);

    // Helper: Deserialize embedding from BLOB
    FaceEmbedding deserializeEmbedding(const QByteArray &data);

    // Helper: Execute query and log errors
    bool executeQuery(const QString &query);
};

#endif // FACEDATABASE_H
