#ifndef FACEDETECTOR_H
#define FACEDETECTOR_H

#include <QObject>
#include <QImage>
#include <QRectF>
#include <QVector>
#include <QString>
#include <opencv2/opencv.hpp>
#include <opencv2/dnn.hpp>
#include <opencv2/objdetect.hpp>

/**
 * @brief Face detection result
 */
struct FaceDetection {
    QRectF bbox;              // Bounding box (normalized 0-1)
    float confidence;         // Detection confidence (0-1)
    QVector<QPointF> landmarks; // 5 facial landmarks (eyes, nose, mouth corners)
};

/**
 * @brief YuNet-based face detector using OpenCV DNN
 *
 * Fast on-device face detection optimized for mobile.
 * Target: 30+ FPS on Sailfish OS devices.
 */
class FaceDetector : public QObject
{
    Q_OBJECT

public:
    explicit FaceDetector(QObject *parent = nullptr);
    ~FaceDetector();

    /**
     * @brief Load the YuNet ONNX model
     * @param modelPath Path to face_detection_yunet_2023mar.onnx
     * @return true if loaded successfully
     */
    bool loadModel(const QString &modelPath);

    /**
     * @brief Detect faces in an image
     * @param image Input image (QImage or cv::Mat, BGR)
     * @param confidenceThreshold Minimum confidence (default: 0.8; YuNet scores
     *        for real faces are typically > 0.9, lower values flood the
     *        database with false positives)
     * @return Vector of detected faces
     */
    QVector<FaceDetection> detect(const QImage &image, float confidenceThreshold = 0.8f);
    QVector<FaceDetection> detect(const cv::Mat &image, float confidenceThreshold = 0.8f);

    /**
     * @brief Check if model is loaded
     */
    bool isLoaded() const { return m_modelLoaded; }

    /**
     * @brief Get input size for the model
     */
    QSize inputSize() const { return m_inputSize; }

    /**
     * @brief Helper: Convert QImage to cv::Mat
     */
    static cv::Mat qImageToCvMat(const QImage &image);

signals:
    void error(const QString &message);

private:
    cv::Ptr<cv::FaceDetectorYN> m_detector;
    bool m_modelLoaded;
    QSize m_inputSize;
};

#endif // FACEDETECTOR_H
