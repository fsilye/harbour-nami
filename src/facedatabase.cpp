#include "facedatabase.h"
#include <QDebug>
#include "logging.h"
#include <QSqlQuery>
#include <QSqlError>
#include <QVariant>
#include <QDataStream>
#include <QBuffer>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>

FaceDatabase::FaceDatabase(QObject *parent)
    : QObject(parent)
    , m_isOpen(false)
{
}

FaceDatabase::~FaceDatabase()
{
    close();
}

bool FaceDatabase::open(const QString &dbPath)
{
    if (m_isOpen) {
        qWarning() << "Database already open";
        return true;
    }

    m_dbPath = dbPath;
    m_db = QSqlDatabase::addDatabase("QSQLITE");
    m_db.setDatabaseName(dbPath);

    if (!m_db.open()) {
        emit error("Failed to open database: " + m_db.lastError().text());
        return false;
    }

    m_isOpen = true;
    qCDebug(lcNami) << "Database opened:" << dbPath;

    // Owner-only: the database holds biometric data (face embeddings)
    QFile::setPermissions(dbPath, QFileDevice::ReadOwner | QFileDevice::WriteOwner);

    // FK constraints are declared in the schema but SQLite only enforces
    // them with this pragma; WAL avoids blocking readers during scans
    QSqlQuery pragma(m_db);
    pragma.exec("PRAGMA foreign_keys = ON");
    pragma.exec("PRAGMA journal_mode = WAL");
    pragma.exec("PRAGMA synchronous = NORMAL");

    // WAL side files inherit creation-time permissions, tighten them too
    QFile::setPermissions(dbPath + "-wal", QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    QFile::setPermissions(dbPath + "-shm", QFileDevice::ReadOwner | QFileDevice::WriteOwner);

    return initializeSchema();
}

void FaceDatabase::close()
{
    if (m_isOpen) {
        m_db.close();
        m_isOpen = false;
        qCDebug(lcNami) << "Database closed";
    }
}

bool FaceDatabase::initializeSchema()
{
    QSqlQuery query(m_db);

    // Photos table
    if (!query.exec(R"(
        CREATE TABLE IF NOT EXISTS photos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            file_path TEXT NOT NULL UNIQUE,
            date_taken TEXT,
            width INTEGER,
            height INTEGER,
            processed_at TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
    )")) {
        emit error("Failed to create photos table: " + query.lastError().text());
        return false;
    }

    // Faces table
    if (!query.exec(R"(
        CREATE TABLE IF NOT EXISTS faces (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            photo_id INTEGER NOT NULL,
            bbox_x REAL NOT NULL,
            bbox_y REAL NOT NULL,
            bbox_width REAL NOT NULL,
            bbox_height REAL NOT NULL,
            confidence REAL NOT NULL,
            embedding BLOB NOT NULL,
            person_id INTEGER DEFAULT -1,
            similarity_score REAL DEFAULT 0.0,
            verified INTEGER DEFAULT 0,
            ignored INTEGER DEFAULT 0,
            detected_at TEXT DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (photo_id) REFERENCES photos(id) ON DELETE CASCADE
        )
    )")) {
        emit error("Failed to create faces table: " + query.lastError().text());
        return false;
    }

    // Migrate existing database if needed (add new columns if they don't exist)
    query.exec("ALTER TABLE faces ADD COLUMN similarity_score REAL DEFAULT 0.0");
    query.exec("ALTER TABLE faces ADD COLUMN verified INTEGER DEFAULT 0");
    query.exec("ALTER TABLE faces ADD COLUMN ignored INTEGER DEFAULT 0");
    query.exec("ALTER TABLE photos ADD COLUMN rotation INTEGER DEFAULT 0");

    // Rejections: "this face is NOT this person", so auto-matching never
    // reassigns a face the user explicitly removed from a person
    if (!query.exec(R"(
        CREATE TABLE IF NOT EXISTS negative_matches (
            face_id INTEGER NOT NULL,
            person_id INTEGER NOT NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (face_id, person_id)
        )
    )")) {
        emit error("Failed to create negative_matches table: " + query.lastError().text());
        return false;
    }

    // People table
    if (!query.exec(R"(
        CREATE TABLE IF NOT EXISTS people (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            contact_id TEXT
        )
    )")) {
        emit error("Failed to create people table: " + query.lastError().text());
        return false;
    }

    // Migrate existing database: link to device contacts
    query.exec("ALTER TABLE people ADD COLUMN contact_id TEXT");

    // Settings table
    if (!query.exec(R"(
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT
        )
    )")) {
        emit error("Failed to create settings table: " + query.lastError().text());
        return false;
    }

    // Create indexes
    query.exec("CREATE INDEX IF NOT EXISTS idx_faces_photo ON faces(photo_id)");
    query.exec("CREATE INDEX IF NOT EXISTS idx_faces_person ON faces(person_id)");
    query.exec("CREATE INDEX IF NOT EXISTS idx_photos_path ON photos(file_path)");

    qCDebug(lcNami) << "Database schema initialized";
    return true;
}

// === Transactions ===

bool FaceDatabase::beginTransaction()
{
    return m_db.transaction();
}

bool FaceDatabase::commitTransaction()
{
    return m_db.commit();
}

bool FaceDatabase::rollbackTransaction()
{
    return m_db.rollback();
}

// === Photo operations ===

int FaceDatabase::addPhoto(const QString &filePath, const QDateTime &dateTaken,
                           int width, int height)
{
    qCDebug(lcNami) << "  → Attempting to insert photo:" << filePath;

    // Check if photo already exists
    QSqlQuery checkQuery(m_db);
    checkQuery.prepare("SELECT id FROM photos WHERE file_path = :file_path");
    checkQuery.bindValue(":file_path", filePath);

    if (checkQuery.exec() && checkQuery.next()) {
        int existingId = checkQuery.value(0).toInt();
        qCDebug(lcNami) << "  ℹ Photo already exists in DB with ID:" << existingId;
        return existingId;  // Return existing photo ID
    }

    QSqlQuery query(m_db);
    query.prepare(R"(
        INSERT INTO photos (file_path, date_taken, width, height)
        VALUES (:file_path, :date_taken, :width, :height)
    )");
    query.bindValue(":file_path", filePath);
    query.bindValue(":date_taken", dateTaken.toString(Qt::ISODate));
    query.bindValue(":width", width);
    query.bindValue(":height", height);

    if (!query.exec()) {
        QString errorMsg = "Failed to add photo: " + query.lastError().text();
        qWarning() << "  ✗ SQL Error:" << errorMsg;
        qWarning() << "  ✗ Query:" << query.lastQuery();
        qCDebug(lcNami) << "  ✗ File path:" << filePath;
        emit error(errorMsg);
        return -1;
    }

    int newId = query.lastInsertId().toInt();
    qCDebug(lcNami) << "  ✓ Photo inserted with ID:" << newId;
    return newId;
}

Photo FaceDatabase::getPhoto(int photoId)
{
    QSqlQuery query(m_db);
    query.prepare("SELECT * FROM photos WHERE id = :id");
    query.bindValue(":id", photoId);

    if (query.exec() && query.next()) {
        Photo photo;
        photo.id = query.value("id").toInt();
        photo.filePath = query.value("file_path").toString();
        photo.dateTaken = QDateTime::fromString(query.value("date_taken").toString(), Qt::ISODate);
        photo.width = query.value("width").toInt();
        photo.height = query.value("height").toInt();
        photo.processedAt = QDateTime::fromString(query.value("processed_at").toString(), Qt::ISODate);
        photo.rotation = query.value("rotation").toInt();
        return photo;
    }

    return Photo{-1, "", QDateTime(), 0, 0, QDateTime(), 0};
}

int FaceDatabase::photoRotation(const QString &filePath)
{
    QSqlQuery query(m_db);
    query.prepare("SELECT rotation FROM photos WHERE file_path = :path");
    query.bindValue(":path", filePath);

    if (query.exec() && query.next()) {
        return query.value(0).toInt();
    }
    return 0;
}

bool FaceDatabase::setPhotoRotation(const QString &filePath, int rotation)
{
    QSqlQuery query(m_db);
    query.prepare("UPDATE photos SET rotation = :rotation WHERE file_path = :path");
    query.bindValue(":rotation", rotation);
    query.bindValue(":path", filePath);

    return query.exec();
}

QVector<Photo> FaceDatabase::getAllPhotos()
{
    QVector<Photo> photos;
    QSqlQuery query(m_db);

    if (query.exec("SELECT * FROM photos ORDER BY date_taken DESC")) {
        while (query.next()) {
            Photo photo;
            photo.id = query.value("id").toInt();
            photo.filePath = query.value("file_path").toString();
            photo.dateTaken = QDateTime::fromString(query.value("date_taken").toString(), Qt::ISODate);
            photo.width = query.value("width").toInt();
            photo.height = query.value("height").toInt();
            photo.processedAt = QDateTime::fromString(query.value("processed_at").toString(), Qt::ISODate);
            photo.rotation = query.value("rotation").toInt();
            photos.append(photo);
        }
    }

    return photos;
}

bool FaceDatabase::markPhotoProcessed(int photoId)
{
    QSqlQuery query(m_db);
    query.prepare("UPDATE photos SET processed_at = :processed_at WHERE id = :id");
    query.bindValue(":processed_at", QDateTime::currentDateTime().toString(Qt::ISODate));
    query.bindValue(":id", photoId);

    return query.exec();
}

// === Face operations ===

int FaceDatabase::addFace(int photoId, const QRectF &bbox, float confidence,
                          const FaceEmbedding &embedding, int personId,
                          float similarityScore, bool verified)
{
    QSqlQuery query(m_db);
    query.prepare(R"(
        INSERT INTO faces (photo_id, bbox_x, bbox_y, bbox_width, bbox_height,
                          confidence, embedding, person_id, similarity_score, verified)
        VALUES (:photo_id, :bbox_x, :bbox_y, :bbox_width, :bbox_height,
                :confidence, :embedding, :person_id, :similarity_score, :verified)
    )");
    query.bindValue(":photo_id", photoId);
    query.bindValue(":bbox_x", bbox.x());
    query.bindValue(":bbox_y", bbox.y());
    query.bindValue(":bbox_width", bbox.width());
    query.bindValue(":bbox_height", bbox.height());
    query.bindValue(":confidence", confidence);
    query.bindValue(":embedding", serializeEmbedding(embedding));
    query.bindValue(":person_id", personId);
    query.bindValue(":similarity_score", similarityScore);
    query.bindValue(":verified", verified ? 1 : 0);

    if (!query.exec()) {
        emit error("Failed to add face: " + query.lastError().text());
        return -1;
    }

    return query.lastInsertId().toInt();
}

Face FaceDatabase::getFace(int faceId)
{
    QSqlQuery query(m_db);
    query.prepare("SELECT * FROM faces WHERE id = :id");
    query.bindValue(":id", faceId);

    if (query.exec() && query.next()) {
        Face face;
        face.id = query.value("id").toInt();
        face.photoId = query.value("photo_id").toInt();
        face.bbox = QRectF(
            query.value("bbox_x").toDouble(),
            query.value("bbox_y").toDouble(),
            query.value("bbox_width").toDouble(),
            query.value("bbox_height").toDouble()
        );
        face.confidence = query.value("confidence").toFloat();
        face.embedding = deserializeEmbedding(query.value("embedding").toByteArray());
        face.personId = query.value("person_id").toInt();
        face.similarityScore = query.value("similarity_score").toFloat();
        face.verified = query.value("verified").toInt() == 1;
        face.detectedAt = QDateTime::fromString(query.value("detected_at").toString(), Qt::ISODate);
        return face;
    }

    return Face{-1, -1, QRectF(), 0.0f, FaceEmbedding(), -1, 0.0f, false, QDateTime()};
}

QVector<Face> FaceDatabase::getFacesForPhoto(int photoId)
{
    QVector<Face> faces;
    QSqlQuery query(m_db);
    query.prepare("SELECT * FROM faces WHERE photo_id = :photo_id");
    query.bindValue(":photo_id", photoId);

    if (query.exec()) {
        while (query.next()) {
            Face face;
            face.id = query.value("id").toInt();
            face.photoId = query.value("photo_id").toInt();
            face.bbox = QRectF(
                query.value("bbox_x").toDouble(),
                query.value("bbox_y").toDouble(),
                query.value("bbox_width").toDouble(),
                query.value("bbox_height").toDouble()
            );
            face.confidence = query.value("confidence").toFloat();
            face.embedding = deserializeEmbedding(query.value("embedding").toByteArray());
            face.personId = query.value("person_id").toInt();
            face.similarityScore = query.value("similarity_score").toFloat();
            face.verified = query.value("verified").toInt() == 1;
            face.detectedAt = QDateTime::fromString(query.value("detected_at").toString(), Qt::ISODate);
            faces.append(face);
        }
    }

    return faces;
}

QVector<Face> FaceDatabase::getUnmappedFaces()
{
    QVector<Face> faces;
    QSqlQuery query(m_db);

    if (query.exec("SELECT * FROM faces WHERE person_id = -1 AND ignored = 0 ORDER BY detected_at DESC")) {
        while (query.next()) {
            Face face;
            face.id = query.value("id").toInt();
            face.photoId = query.value("photo_id").toInt();
            face.bbox = QRectF(
                query.value("bbox_x").toDouble(),
                query.value("bbox_y").toDouble(),
                query.value("bbox_width").toDouble(),
                query.value("bbox_height").toDouble()
            );
            face.confidence = query.value("confidence").toFloat();
            face.embedding = deserializeEmbedding(query.value("embedding").toByteArray());
            face.personId = query.value("person_id").toInt();
            face.similarityScore = query.value("similarity_score").toFloat();
            face.verified = query.value("verified").toInt() == 1;
            face.detectedAt = QDateTime::fromString(query.value("detected_at").toString(), Qt::ISODate);
            faces.append(face);
        }
    }

    return faces;
}

bool FaceDatabase::updateFacePersonMapping(int faceId, int personId)
{
    QSqlQuery query(m_db);
    query.prepare("UPDATE faces SET person_id = :person_id WHERE id = :id");
    query.bindValue(":person_id", personId);
    query.bindValue(":id", faceId);

    return query.exec();
}

bool FaceDatabase::updateFaceMetadata(int faceId, float similarityScore, bool verified)
{
    QSqlQuery query(m_db);
    query.prepare("UPDATE faces SET similarity_score = :similarity_score, verified = :verified WHERE id = :id");
    query.bindValue(":similarity_score", similarityScore);
    query.bindValue(":verified", verified ? 1 : 0);
    query.bindValue(":id", faceId);

    return query.exec();
}

bool FaceDatabase::removeFaceFromPerson(int faceId)
{
    QSqlQuery query(m_db);
    query.prepare("UPDATE faces SET person_id = -1, verified = 0 WHERE id = :id");
    query.bindValue(":id", faceId);

    return query.exec();
}

bool FaceDatabase::removePersonFromPhoto(int personId, int photoId)
{
    // Collect the affected faces first so each rejection is remembered
    QVector<int> faceIds;
    QSqlQuery sel(m_db);
    sel.prepare("SELECT id FROM faces WHERE photo_id = :photo AND person_id = :person");
    sel.bindValue(":photo", photoId);
    sel.bindValue(":person", personId);
    if (sel.exec()) {
        while (sel.next()) {
            faceIds.append(sel.value(0).toInt());
        }
    }

    for (int faceId : faceIds) {
        addNegativeMatch(faceId, personId);
    }

    QSqlQuery upd(m_db);
    upd.prepare("UPDATE faces SET person_id = -1, verified = 0 "
                "WHERE photo_id = :photo AND person_id = :person");
    upd.bindValue(":photo", photoId);
    upd.bindValue(":person", personId);

    return upd.exec();
}

bool FaceDatabase::setFaceIgnored(int faceId, bool ignored)
{
    QSqlQuery query(m_db);
    query.prepare("UPDATE faces SET ignored = :ignored WHERE id = :id");
    query.bindValue(":ignored", ignored ? 1 : 0);
    query.bindValue(":id", faceId);

    return query.exec();
}

bool FaceDatabase::addNegativeMatch(int faceId, int personId)
{
    QSqlQuery query(m_db);
    query.prepare("INSERT OR IGNORE INTO negative_matches (face_id, person_id) VALUES (:face_id, :person_id)");
    query.bindValue(":face_id", faceId);
    query.bindValue(":person_id", personId);

    return query.exec();
}

bool FaceDatabase::hasNegativeMatch(int faceId, int personId)
{
    QSqlQuery query(m_db);
    query.prepare("SELECT 1 FROM negative_matches WHERE face_id = :face_id AND person_id = :person_id");
    query.bindValue(":face_id", faceId);
    query.bindValue(":person_id", personId);

    return query.exec() && query.next();
}

bool FaceDatabase::deleteFacesForPhoto(int photoId)
{
    QSqlQuery cleanup(m_db);
    cleanup.prepare(R"(
        DELETE FROM negative_matches
        WHERE face_id IN (SELECT id FROM faces WHERE photo_id = :photo_id)
    )");
    cleanup.bindValue(":photo_id", photoId);
    cleanup.exec();

    QSqlQuery query(m_db);
    query.prepare("DELETE FROM faces WHERE photo_id = :photo_id");
    query.bindValue(":photo_id", photoId);

    return query.exec();
}

QSet<QString> FaceDatabase::getProcessedFilePaths()
{
    QSet<QString> paths;
    QSqlQuery query(m_db);

    if (query.exec("SELECT file_path FROM photos WHERE processed_at IS NOT NULL")) {
        while (query.next()) {
            paths.insert(query.value(0).toString());
        }
    }

    return paths;
}

// === Person operations ===

int FaceDatabase::createPerson(const QString &name)
{
    QSqlQuery query(m_db);
    query.prepare("INSERT INTO people (name) VALUES (:name)");
    query.bindValue(":name", name);

    if (!query.exec()) {
        emit error("Failed to create person: " + query.lastError().text());
        return -1;
    }

    return query.lastInsertId().toInt();
}

Person FaceDatabase::getPerson(int personId)
{
    QSqlQuery query(m_db);
    query.prepare(R"(
        SELECT p.*, COUNT(DISTINCT f.photo_id) as photo_count
        FROM people p
        LEFT JOIN faces f ON f.person_id = p.id
        WHERE p.id = :id
        GROUP BY p.id
    )");
    query.bindValue(":id", personId);

    if (query.exec() && query.next()) {
        Person person;
        person.id = query.value("id").toInt();
        person.name = query.value("name").toString();
        person.createdAt = QDateTime::fromString(query.value("created_at").toString(), Qt::ISODate);
        person.photoCount = query.value("photo_count").toInt();
        person.contactId = query.value("contact_id").toString();
        return person;
    }

    return Person{-1, "", QDateTime(), 0, QString()};
}

QVector<Person> FaceDatabase::getAllPeople()
{
    QVector<Person> people;
    QSqlQuery query(m_db);

    if (query.exec(R"(
        SELECT p.*, COUNT(DISTINCT f.photo_id) as photo_count
        FROM people p
        LEFT JOIN faces f ON f.person_id = p.id
        GROUP BY p.id
        ORDER BY p.name ASC
    )")) {
        while (query.next()) {
            Person person;
            person.id = query.value("id").toInt();
            person.name = query.value("name").toString();
            person.createdAt = QDateTime::fromString(query.value("created_at").toString(), Qt::ISODate);
            person.photoCount = query.value("photo_count").toInt();
            person.contactId = query.value("contact_id").toString();
            people.append(person);
        }
    }

    return people;
}

bool FaceDatabase::updatePersonName(int personId, const QString &name)
{
    QSqlQuery query(m_db);
    query.prepare("UPDATE people SET name = :name WHERE id = :id");
    query.bindValue(":name", name);
    query.bindValue(":id", personId);

    return query.exec();
}

bool FaceDatabase::setPersonContact(int personId, const QString &contactId)
{
    QSqlQuery query(m_db);
    query.prepare("UPDATE people SET contact_id = :contact_id WHERE id = :id");
    // Store NULL rather than "" when unlinking
    query.bindValue(":contact_id", contactId.isEmpty() ? QVariant() : QVariant(contactId));
    query.bindValue(":id", personId);

    return query.exec();
}

bool FaceDatabase::deletePerson(int personId)
{
    m_db.transaction();

    // Unmap all faces for this person
    QSqlQuery query1(m_db);
    query1.prepare("UPDATE faces SET person_id = -1 WHERE person_id = :person_id");
    query1.bindValue(":person_id", personId);

    if (!query1.exec()) {
        m_db.rollback();
        return false;
    }

    // Delete person
    QSqlQuery query2(m_db);
    query2.prepare("DELETE FROM people WHERE id = :id");
    query2.bindValue(":id", personId);

    if (!query2.exec()) {
        m_db.rollback();
        return false;
    }

    // Drop rejections referencing this person
    QSqlQuery query3(m_db);
    query3.prepare("DELETE FROM negative_matches WHERE person_id = :person_id");
    query3.bindValue(":person_id", personId);
    query3.exec();

    m_db.commit();
    return true;
}

bool FaceDatabase::mergePersons(int fromPersonId, int intoPersonId)
{
    m_db.transaction();

    // Reassign faces (verified flags and similarity scores carry over)
    QSqlQuery moveFaces(m_db);
    moveFaces.prepare("UPDATE faces SET person_id = :into WHERE person_id = :from");
    moveFaces.bindValue(":into", intoPersonId);
    moveFaces.bindValue(":from", fromPersonId);
    if (!moveFaces.exec()) {
        m_db.rollback();
        return false;
    }

    // A rejection of the duplicate is a rejection of the same human
    QSqlQuery moveRejections(m_db);
    moveRejections.prepare(R"(
        INSERT OR IGNORE INTO negative_matches (face_id, person_id)
        SELECT face_id, :into FROM negative_matches WHERE person_id = :from
    )");
    moveRejections.bindValue(":into", intoPersonId);
    moveRejections.bindValue(":from", fromPersonId);
    if (!moveRejections.exec()) {
        m_db.rollback();
        return false;
    }

    QSqlQuery dropRejections(m_db);
    dropRejections.prepare("DELETE FROM negative_matches WHERE person_id = :from");
    dropRejections.bindValue(":from", fromPersonId);
    dropRejections.exec();

    QSqlQuery dropPerson(m_db);
    dropPerson.prepare("DELETE FROM people WHERE id = :from");
    dropPerson.bindValue(":from", fromPersonId);
    if (!dropPerson.exec()) {
        m_db.rollback();
        return false;
    }

    m_db.commit();
    return true;
}

QVector<Face> FaceDatabase::getFacesForPerson(int personId)
{
    QVector<Face> faces;
    QSqlQuery query(m_db);
    query.prepare("SELECT * FROM faces WHERE person_id = :person_id");
    query.bindValue(":person_id", personId);

    if (query.exec()) {
        while (query.next()) {
            Face face;
            face.id = query.value("id").toInt();
            face.photoId = query.value("photo_id").toInt();
            face.bbox = QRectF(
                query.value("bbox_x").toDouble(),
                query.value("bbox_y").toDouble(),
                query.value("bbox_width").toDouble(),
                query.value("bbox_height").toDouble()
            );
            face.confidence = query.value("confidence").toFloat();
            face.embedding = deserializeEmbedding(query.value("embedding").toByteArray());
            face.personId = query.value("person_id").toInt();
            face.similarityScore = query.value("similarity_score").toFloat();
            face.verified = query.value("verified").toInt() == 1;
            face.detectedAt = QDateTime::fromString(query.value("detected_at").toString(), Qt::ISODate);
            faces.append(face);
        }
    }

    return faces;
}

Face FaceDatabase::getBestFaceForPerson(int personId)
{
    QSqlQuery query(m_db);
    query.prepare(R"(
        SELECT id FROM faces
        WHERE person_id = :person_id
        ORDER BY verified DESC, similarity_score DESC, confidence DESC
        LIMIT 1
    )");
    query.bindValue(":person_id", personId);

    if (query.exec() && query.next()) {
        return getFace(query.value(0).toInt());
    }

    return Face{-1, -1, QRectF(), 0.0f, FaceEmbedding(), -1, 0.0f, false, QDateTime()};
}

QVector<FaceEmbedding> FaceDatabase::getPersonExemplars(int personId, int maxCount)
{
    QVector<FaceEmbedding> exemplars;

    // User-verified faces define the person; only fall back to unverified
    // detections when there is no verified face yet, so a bad auto-match
    // cannot poison the person's representation
    QSqlQuery query(m_db);
    query.prepare(R"(
        SELECT embedding FROM faces
        WHERE person_id = :person_id AND verified = 1
        ORDER BY similarity_score DESC, confidence DESC
        LIMIT :limit
    )");
    query.bindValue(":person_id", personId);
    query.bindValue(":limit", maxCount);

    if (query.exec()) {
        while (query.next()) {
            exemplars.append(deserializeEmbedding(query.value(0).toByteArray()));
        }
    }

    if (exemplars.isEmpty()) {
        QSqlQuery fallback(m_db);
        fallback.prepare(R"(
            SELECT embedding FROM faces
            WHERE person_id = :person_id
            ORDER BY confidence DESC
            LIMIT :limit
        )");
        fallback.bindValue(":person_id", personId);
        fallback.bindValue(":limit", maxCount);

        if (fallback.exec()) {
            while (fallback.next()) {
                exemplars.append(deserializeEmbedding(fallback.value(0).toByteArray()));
            }
        }
    }

    return exemplars;
}

// === GDPR ===

QVariantMap FaceDatabase::exportPersonData(int personId)
{
    QVariantMap data;
    Person person = getPerson(personId);

    data["person_id"] = person.id;
    data["name"] = person.name;
    data["created_at"] = person.createdAt.toString(Qt::ISODate);

    QVariantList facesData;
    QVector<Face> faces = getFacesForPerson(personId);

    for (const Face &face : faces) {
        QVariantMap faceData;
        faceData["face_id"] = face.id;
        faceData["photo_id"] = face.photoId;
        faceData["confidence"] = face.confidence;
        faceData["detected_at"] = face.detectedAt.toString(Qt::ISODate);
        facesData.append(faceData);
    }

    data["faces"] = facesData;
    data["total_faces"] = faces.size();

    return data;
}

bool FaceDatabase::deleteAllData()
{
    m_db.transaction();

    QSqlQuery query(m_db);

    if (!query.exec("DELETE FROM negative_matches") ||
        !query.exec("DELETE FROM faces") ||
        !query.exec("DELETE FROM people") ||
        !query.exec("DELETE FROM photos")) {
        m_db.rollback();
        return false;
    }

    m_db.commit();

    // Reclaim space and purge deleted embeddings from free pages
    query.exec("VACUUM");
    return true;
}

bool FaceDatabase::clearFaceData()
{
    m_db.transaction();

    QSqlQuery query(m_db);

    // Photos records are kept, but they must be re-processed
    if (!query.exec("DELETE FROM negative_matches") ||
        !query.exec("DELETE FROM faces") ||
        !query.exec("DELETE FROM people") ||
        !query.exec("UPDATE photos SET processed_at = NULL")) {
        m_db.rollback();
        return false;
    }

    m_db.commit();
    return true;
}

QString FaceDatabase::getSetting(const QString &key, const QString &defaultValue)
{
    QSqlQuery query(m_db);
    query.prepare("SELECT value FROM settings WHERE key = :key");
    query.bindValue(":key", key);

    if (query.exec() && query.next()) {
        return query.value(0).toString();
    }

    return defaultValue;
}

bool FaceDatabase::setSetting(const QString &key, const QString &value)
{
    QSqlQuery query(m_db);
    query.prepare("INSERT OR REPLACE INTO settings (key, value) VALUES (:key, :value)");
    query.bindValue(":key", key);
    query.bindValue(":value", value);

    return query.exec();
}

QVariantMap FaceDatabase::getStatistics()
{
    QVariantMap stats;
    QSqlQuery query(m_db);

    if (query.exec("SELECT COUNT(*) FROM photos")) {
        query.next();
        stats["total_photos"] = query.value(0).toInt();
    }

    if (query.exec("SELECT COUNT(*) FROM faces")) {
        query.next();
        stats["total_faces"] = query.value(0).toInt();
    }

    if (query.exec("SELECT COUNT(*) FROM people")) {
        query.next();
        stats["total_people"] = query.value(0).toInt();
    }

    if (query.exec("SELECT COUNT(*) FROM faces WHERE person_id = -1 AND ignored = 0")) {
        query.next();
        stats["unmapped_faces"] = query.value(0).toInt();
    }

    stats["db_size_bytes"] = QFileInfo(m_dbPath).size();

    return stats;
}

// === Helpers ===

QByteArray FaceDatabase::serializeEmbedding(const FaceEmbedding &embedding)
{
    QByteArray data;
    QDataStream stream(&data, QIODevice::WriteOnly);

    stream << static_cast<quint32>(embedding.size());
    for (float val : embedding) {
        stream << val;
    }

    return data;
}

FaceEmbedding FaceDatabase::deserializeEmbedding(const QByteArray &data)
{
    QDataStream stream(data);
    quint32 size;
    stream >> size;

    FaceEmbedding embedding(size);
    for (quint32 i = 0; i < size; i++) {
        stream >> embedding[i];
    }

    return embedding;
}
