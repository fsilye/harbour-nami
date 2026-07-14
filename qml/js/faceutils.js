// Helpers for the image://faces thumbnail provider
.pragma library

// Cropped face thumbnail URL (square, margin around the bbox)
function cropUrl(photoPath, x, y, w, h, round) {
    if (!photoPath || !(w > 0) || !(h > 0)) {
        return ""
    }
    var url = "image://faces/crop?path=" + encodeURIComponent(photoPath)
            + "&x=" + x + "&y=" + y + "&w=" + w + "&h=" + h
    if (round) {
        url += "&round=1"
    }
    return url
}

// Avatar URL for a person's best face; "" when the person has none.
// Round by default (list circles); pass round=false for square tiles (grid)
function personAvatarUrl(pipeline, personId, round) {
    if (!pipeline || !pipeline.initialized) {
        return ""
    }
    var face = pipeline.getPersonBestFace(personId)
    if (!face || !face.photo_path) {
        return ""
    }
    return cropUrl(face.photo_path, face.bbox_x, face.bbox_y,
                   face.bbox_width, face.bbox_height,
                   round === undefined ? true : round)
}
