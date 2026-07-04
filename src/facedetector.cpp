#include "facedetector.h"
#include <QDebug>
#include <algorithm>
#include <cmath>

FaceDetector::FaceDetector(QObject *parent)
    : QObject(parent)
    , m_modelLoaded(false)
    , m_inputSize(640, 640)  // Fixed YuNet input size (good balance for mobile)
{
}

FaceDetector::~FaceDetector()
{
}

bool FaceDetector::loadModel(const QString &modelPath)
{
    try {
        qDebug() << "Loading YuNet face detection model from:" << modelPath;

        // Create FaceDetectorYN with OpenCV API
        // Parameters: model_path, config_path, input_size, score_threshold, nms_threshold, top_k, backend_id, target_id
        m_detector = cv::FaceDetectorYN::create(
            modelPath.toStdString(),  // model path
            "",                        // config path (empty for ONNX)
            cv::Size(m_inputSize.width(), m_inputSize.height()),  // input size
            0.6f,                      // score threshold (will be overridden in detect())
            0.3f,                      // NMS threshold
            5000,                      // top_k
            cv::dnn::DNN_BACKEND_OPENCV,   // backend
            cv::dnn::DNN_TARGET_CPU        // target
        );

        if (m_detector.empty()) {
            emit error("Failed to create YuNet detector");
            return false;
        }

        m_modelLoaded = true;
        qDebug() << "YuNet model loaded successfully";
        qDebug() << "Fixed input size:" << m_inputSize.width() << "x" << m_inputSize.height()
                 << "(all images will be resized to this)";

        return true;
    }
    catch (const cv::Exception &e) {
        QString errorMsg = QString("OpenCV exception loading model: %1").arg(e.what());
        qWarning() << errorMsg;
        emit error(errorMsg);
        return false;
    }
}

QVector<FaceDetection> FaceDetector::detect(const QImage &image, float confidenceThreshold)
{
    qDebug() << "QImage detection requested - size:" << image.width() << "x" << image.height();
    cv::Mat mat = qImageToCvMat(image);
    qDebug() << "Converted to cv::Mat - size:" << mat.cols << "x" << mat.rows;
    return detect(mat, confidenceThreshold);
}

QVector<FaceDetection> FaceDetector::detect(const cv::Mat &image, float confidenceThreshold)
{
    if (!m_modelLoaded) {
        emit error("Model not loaded");
        return QVector<FaceDetection>();
    }

    if (image.empty()) {
        emit error("Empty input image");
        return QVector<FaceDetection>();
    }

    qDebug() << "=== Face Detection Start ===";
    qDebug() << "Input image size:" << image.cols << "x" << image.rows << "channels:" << image.channels();
    qDebug() << "Confidence threshold:" << confidenceThreshold;

    try {
        // Downscale with a uniform factor so faces are not distorted; YuNet
        // supports arbitrary input sizes via setInputSize
        const int maxSide = qMax(m_inputSize.width(), m_inputSize.height());
        float scale = 1.0f;
        int longest = std::max(image.cols, image.rows);
        if (longest > maxSide) {
            scale = static_cast<float>(maxSide) / longest;
        }

        int newW = std::max(1, static_cast<int>(std::round(image.cols * scale)));
        int newH = std::max(1, static_cast<int>(std::round(image.rows * scale)));

        cv::Mat resizedImage;
        if (scale < 1.0f) {
            cv::resize(image, resizedImage, cv::Size(newW, newH), 0, 0, cv::INTER_AREA);
        } else {
            resizedImage = image;
        }

        m_detector->setInputSize(cv::Size(newW, newH));

        // Single uniform factor to map detections back to original coordinates
        float scaleX = static_cast<float>(image.cols) / newW;
        float scaleY = static_cast<float>(image.rows) / newH;

        qDebug() << "Resized to" << newW << "x" << newH << "scale:" << scaleX;

        // Set score threshold
        m_detector->setScoreThreshold(confidenceThreshold);

        // Detect faces on resized image
        cv::Mat faces;
        qDebug() << "Running YuNet detector...";
        m_detector->detect(resizedImage, faces);

        qDebug() << "Detection complete - faces matrix: rows=" << faces.rows << "cols=" << faces.cols << "type=" << faces.type();

        // Convert results
        QVector<FaceDetection> detections;

        if (faces.rows > 0) {
            qDebug() << "Found" << faces.rows << "faces";

            for (int i = 0; i < faces.rows; i++) {
                FaceDetection detection;

                // YuNet output format per row: [x, y, w, h, x_re, y_re, x_le, y_le, x_nt, y_nt, x_rcm, y_rcm, x_lcm, y_lcm, score]
                // Coordinates are in pixels

                float x = faces.at<float>(i, 0);
                float y = faces.at<float>(i, 1);
                float w = faces.at<float>(i, 2);
                float h = faces.at<float>(i, 3);
                float score = faces.at<float>(i, 14);

                qDebug() << "  Face" << i << "- bbox (pixels in detector input):" << x << y << w << h << "score:" << score;

                // Scale coordinates back to original image size
                float origX = x * scaleX;
                float origY = y * scaleY;
                float origW = w * scaleX;
                float origH = h * scaleY;

                qDebug() << "  Face" << i << "- bbox (pixels in original image):" << origX << origY << origW << origH;

                // Normalize to [0-1] based on original image size
                detection.bbox = QRectF(
                    origX / image.cols,
                    origY / image.rows,
                    origW / image.cols,
                    origH / image.rows
                );
                detection.confidence = score;

                // Extract 5 landmarks and normalize (also scale back to original)
                for (int j = 0; j < 5; j++) {
                    float lx = (faces.at<float>(i, 4 + j*2) * scaleX) / image.cols;
                    float ly = (faces.at<float>(i, 5 + j*2) * scaleY) / image.rows;
                    detection.landmarks.append(QPointF(lx, ly));
                }

                detections.append(detection);
            }
        } else {
            qDebug() << "No faces detected";
        }

        qDebug() << "=== Detection Complete: Found" << detections.size() << "faces ===";

        return detections;
    }
    catch (const cv::Exception &e) {
        QString errorMsg = QString("OpenCV exception during detection: %1").arg(e.what());
        qWarning() << errorMsg;
        emit error(errorMsg);
        return QVector<FaceDetection>();
    }
}

cv::Mat FaceDetector::qImageToCvMat(const QImage &image)
{
    // OpenCV convention is BGR; both YuNet and the recognition preprocessing
    // expect it, so everything downstream works on BGR mats
    QImage rgb = image.convertToFormat(QImage::Format_RGB888);
    cv::Mat rgbMat(rgb.height(), rgb.width(), CV_8UC3,
                   const_cast<uchar*>(rgb.bits()), rgb.bytesPerLine());

    cv::Mat bgr;
    cv::cvtColor(rgbMat, bgr, cv::COLOR_RGB2BGR);
    return bgr;
}
