/* Dummy hb.h - HarfBuzz disabled for cpfont build */
#ifndef HB_H
#define HB_H

/* Minimal typedefs to make ft-hb.c compile */
typedef struct hb_font_t hb_font_t;
typedef struct hb_buffer_t hb_buffer_t;
typedef struct hb_feature_t hb_feature_t;
typedef struct hb_glyph_info_t hb_glyph_info_t;
typedef struct hb_glyph_position_t hb_glyph_position_t;
typedef struct hb_segment_properties_t hb_segment_properties_t;
typedef struct hb_unicode_funcs_t hb_unicode_funcs_t;
typedef int hb_bool_t;
typedef unsigned int hb_codepoint_t;
typedef unsigned int hb_mask_t;
typedef uint32_t hb_tag_t;

#define HB_TAG(c1,c2,c3,c4) ((hb_tag_t)((((uint32_t)(c1))<<24)|(((uint32_t)(c2))<<16)|(((uint32_t)(c3))<<8)|((uint32_t)(c4))))

/* Dummy functions - never called because HarfBuzz is disabled at runtime */
static inline hb_buffer_t* hb_buffer_create(void) { return 0; }
static inline void hb_buffer_destroy(hb_buffer_t* b) {}
static inline void hb_buffer_add_utf8(hb_buffer_t* b, const char* t, int l, unsigned int o, int c) {}
static inline void hb_buffer_guess_segment_properties(hb_buffer_t* b) {}
static inline unsigned int hb_buffer_get_length(hb_buffer_t* b) { return 0; }
static inline hb_glyph_info_t* hb_buffer_get_glyph_infos(hb_buffer_t* b, unsigned int* l) { return 0; }
static inline hb_glyph_position_t* hb_buffer_get_glyph_positions(hb_buffer_t* b, unsigned int* l) { return 0; }
static inline void hb_shape(hb_font_t* f, hb_buffer_t* b, const hb_feature_t* fe, unsigned int n) {}

#endif
