#include <android/log.h>
#include <stdlib.h>
#include <string.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_ADVANCES_H

// Forward declarations
void* cpft_load_face_with_fallback(const unsigned char* data, size_t len,
                                   const unsigned char* fb_data, size_t fb_len);

#define LOG_TAG "cpfont_ft"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

static FT_Library g_lib = NULL;

typedef struct {
    FT_Face face;
    FT_Face fallback;
} cpfont_face_t;

// Error codes matching FreeType:
// 0 = OK
// 1 = Cannot_Open_Resource
// 2 = Unknown_File_Format
// 3 = Invalid_File_Format
// 4 = Invalid_Version
// 5 = Invalid_Argument
// 6 = Unimplemented_Feature
// etc.

int cpft_init() {
    if (g_lib) return 0;
    FT_Error err = FT_Init_FreeType(&g_lib);
    if (err) {
        LOGE("FT_Init_FreeType failed: %d", err);
        return (int)err;
    }
    LOGI("FreeType initialized");
    return 0;
}

void cpft_deinit() {
    if (g_lib) {
        FT_Done_FreeType(g_lib);
        g_lib = NULL;
    }
}

static FT_ULong cp_to_index(FT_Face face, unsigned int cp) {
    FT_ULong idx = FT_Get_Char_Index(face, (FT_ULong)cp);
    return idx;
}

void* cpft_load_face(const unsigned char* data, size_t len) {
    return cpft_load_face_with_fallback(data, len, NULL, 0);
}

void* cpft_load_face_with_fallback(const unsigned char* data, size_t len,
                                   const unsigned char* fb_data, size_t fb_len) {
    if (!g_lib) {
        LOGE("Library not initialized");
        return NULL;
    }
    cpfont_face_t* cf = (cpfont_face_t*)calloc(1, sizeof(cpfont_face_t));
    if (!cf) return NULL;

    FT_Error err = FT_New_Memory_Face(g_lib, data, (FT_Long)len, 0, &cf->face);
    if (err) {
        LOGE("FT_New_Memory_Face failed: %d", err);
        free(cf);
        return NULL;
    }
    LOGI("Face loaded: %s %s, glyphs: %ld", cf->face->family_name, cf->face->style_name, (long)cf->face->num_glyphs);

    if (fb_data && fb_len > 0) {
        err = FT_New_Memory_Face(g_lib, fb_data, (FT_Long)fb_len, 0, &cf->fallback);
        if (err) {
            LOGE("FT_New_Memory_Face (fallback) failed: %d", err);
            cf->fallback = NULL;
        } else {
            LOGI("Fallback loaded: %s %s", cf->fallback->family_name, cf->fallback->style_name);
        }
    }
    return cf;
}

void cpft_done_face(void* face) {
    cpfont_face_t* cf = (cpfont_face_t*)face;
    if (!cf) return;
    if (cf->face) FT_Done_Face(cf->face);
    if (cf->fallback) FT_Done_Face(cf->fallback);
    free(cf);
}

int cpft_set_size(void* face, int ppem) {
    cpfont_face_t* cf = (cpfont_face_t*)face;
    if (!cf || !cf->face) return 6;
    FT_Error err = FT_Set_Pixel_Sizes(cf->face, 0, (FT_UInt)ppem);
    if (err) {
        LOGE("FT_Set_Pixel_Sizes failed: %d (ppem=%d)", err, ppem);
        return (int)err;
    }
    if (cf->fallback) {
        FT_Set_Pixel_Sizes(cf->fallback, 0, (FT_UInt)ppem);
    }
    return 0;
}

int cpft_get_metrics(void* face, int* ascender, int* descender, int* height) {
    cpfont_face_t* cf = (cpfont_face_t*)face;
    if (!cf || !cf->face) return 6;
    FT_Size_Metrics m = cf->face->size->metrics;
    *ascender = m.ascender;
    *descender = m.descender;
    *height = m.height;
    return 0;
}

int cpft_has_glyph(void* face, unsigned int cp) {
    cpfont_face_t* cf = (cpfont_face_t*)face;
    if (!cf || !cf->face) return 0;
    FT_ULong idx = cp_to_index(cf->face, cp);
    return idx != 0 ? 1 : 0;
}

int cpft_get_advance(void* face, unsigned int cp) {
    cpfont_face_t* cf = (cpfont_face_t*)face;
    if (!cf || !cf->face) return 0;
    FT_ULong idx = cp_to_index(cf->face, cp);
    if (idx == 0 && cf->fallback) {
        idx = cp_to_index(cf->fallback, cp);
    }
    if (idx == 0) return 0;
    FT_Fixed adv;
    FT_Error err = FT_Get_Advance(cf->face, idx, FT_LOAD_DEFAULT, &adv);
    if (err) return 0;
    // adv is in 26.6 fixed point (1/64 px)
    return (int)adv;
}

int cpft_get_kern(void* face, unsigned int leftCp, unsigned int rightCp) {
    cpfont_face_t* cf = (cpfont_face_t*)face;
    if (!cf || !cf->face) return 0;
    FT_ULong left = cp_to_index(cf->face, leftCp);
    FT_ULong right = cp_to_index(cf->face, rightCp);
    if (left == 0 || right == 0) return 0;
    FT_Vector kerning;
    FT_Error err = FT_Get_Kerning(cf->face, left, right, FT_KERNING_DEFAULT, &kerning);
    if (err) return 0;
    // kerning.x is in 26.6 fixed point (1/64 px). Convert to 1/16 px: divide by 4
    return (int)(kerning.x / 4);
}

int cpft_get_units_per_em(void* face) {
    cpfont_face_t* cf = (cpfont_face_t*)face;
    if (!cf || !cf->face) return 1000;
    return (int)cf->face->units_per_EM;
}

int cpft_render_glyph(void* face, unsigned int cp,
                      unsigned char** out_buf,
                      int* out_w, int* out_h, int* out_pitch,
                      int* out_left, int* out_top, int* out_advance_x) {
    cpfont_face_t* cf = (cpfont_face_t*)face;
    if (!cf || !cf->face) {
        LOGE("cpft_render_glyph: null face");
        return 6;
    }

    FT_Face active = cf->face;
    FT_ULong idx = cp_to_index(active, cp);

    if (idx == 0 && cf->fallback) {
        active = cf->fallback;
        idx = cp_to_index(active, cp);
    }

    if (idx == 0) {
        *out_w = 0;
        *out_h = 0;
        *out_pitch = 0;
        *out_left = 0;
        *out_top = 0;
        *out_advance_x = 0;
        *out_buf = NULL;
        LOGI("Glyph NOT FOUND: cp=%u (0x%X)", cp, cp);
        return 0;
    }

    LOGI("Glyph FOUND: cp=%u (0x%X) idx=%lu", cp, cp, (unsigned long)idx);

    FT_Error err = FT_Load_Glyph(active, idx, FT_LOAD_DEFAULT);
    if (err) {
        LOGE("FT_Load_Glyph failed: %d (cp=%u, idx=%lu)", err, cp, (unsigned long)idx);
        return (int)err;
    }

    err = FT_Render_Glyph(active->glyph, FT_RENDER_MODE_NORMAL);
    if (err) {
        LOGE("FT_Render_Glyph failed: %d (cp=%u)", err, cp);
        return (int)err;
    }

    FT_Bitmap* bm = &active->glyph->bitmap;
    LOGI("Glyph RENDERED: cp=%u size=%dx%d", cp, (int)bm->width, (int)bm->rows);
    *out_w = (int)bm->width;
    *out_h = (int)bm->rows;
    *out_pitch = (int)bm->pitch;
    *out_left = (int)active->glyph->bitmap_left;
    *out_top = (int)active->glyph->bitmap_top;
    *out_advance_x = (int)active->glyph->advance.x;

    int size = bm->width * bm->rows;
    if (size > 0) {
        *out_buf = (unsigned char*)malloc(size);
        if (*out_buf) {
            // Copy row by row, skipping pitch padding
            for (int row = 0; row < bm->rows; row++) {
                memcpy(*out_buf + row * bm->width,
                       bm->buffer + row * bm->pitch,
                       bm->width);
            }
        }
    } else {
        *out_buf = NULL;
    }

    return 0;
}

void cpft_free_bitmap(unsigned char* buf) {
    if (buf) free(buf);
}
