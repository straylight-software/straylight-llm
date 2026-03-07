/*
 * C bindings for tokenizers-cpp
 * 
 * This provides a C ABI wrapper around the tokenizers-cpp library
 * for use from Haskell FFI.
 */
#ifndef TOKENIZERS_C_H
#define TOKENIZERS_C_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque handle to a tokenizer */
typedef struct TokenizerHandle* tokenizer_t;

/* ═══════════════════════════════════════════════════════════════════════════
 * Construction / Destruction
 * ═══════════════════════════════════════════════════════════════════════════ */

/**
 * Create a tokenizer from HuggingFace JSON blob (tokenizer.json)
 * 
 * @param json_data Pointer to JSON data
 * @param json_len Length of JSON data
 * @return Tokenizer handle, or NULL on error
 */
tokenizer_t tokenizer_from_json(const char* json_data, size_t json_len);

/**
 * Create a tokenizer from SentencePiece model blob
 * 
 * @param model_data Pointer to model data
 * @param model_len Length of model data
 * @return Tokenizer handle, or NULL on error
 */
tokenizer_t tokenizer_from_sentencepiece(const char* model_data, size_t model_len);

/**
 * Free a tokenizer
 * 
 * @param tok Tokenizer handle (may be NULL)
 */
void tokenizer_free(tokenizer_t tok);

/* ═══════════════════════════════════════════════════════════════════════════
 * Encoding
 * ═══════════════════════════════════════════════════════════════════════════ */

/**
 * Encode text to token IDs
 * 
 * @param tok Tokenizer handle
 * @param text UTF-8 text to encode
 * @param text_len Length of text in bytes
 * @param out_ids Output buffer for token IDs (caller allocated)
 * @param out_capacity Capacity of output buffer
 * @return Number of tokens encoded, or -1 on error
 *         If return > out_capacity, buffer was too small
 */
int32_t tokenizer_encode(
    tokenizer_t tok,
    const char* text,
    size_t text_len,
    int32_t* out_ids,
    size_t out_capacity
);

/**
 * Encode text and allocate result buffer
 * 
 * @param tok Tokenizer handle
 * @param text UTF-8 text to encode
 * @param text_len Length of text in bytes
 * @param out_ids Output pointer to allocated buffer (caller must free with tokenizer_free_ids)
 * @param out_len Output number of tokens
 * @return 0 on success, -1 on error
 */
int32_t tokenizer_encode_alloc(
    tokenizer_t tok,
    const char* text,
    size_t text_len,
    int32_t** out_ids,
    size_t* out_len
);

/**
 * Free token ID buffer allocated by tokenizer_encode_alloc
 */
void tokenizer_free_ids(int32_t* ids);

/* ═══════════════════════════════════════════════════════════════════════════
 * Decoding
 * ═══════════════════════════════════════════════════════════════════════════ */

/**
 * Decode token IDs to text
 * 
 * @param tok Tokenizer handle
 * @param ids Token IDs to decode
 * @param ids_len Number of token IDs
 * @param out_text Output buffer for text (caller allocated)
 * @param out_capacity Capacity of output buffer
 * @return Number of bytes written, or -1 on error
 *         If return > out_capacity, buffer was too small
 */
int32_t tokenizer_decode(
    tokenizer_t tok,
    const int32_t* ids,
    size_t ids_len,
    char* out_text,
    size_t out_capacity
);

/**
 * Decode token IDs and allocate result buffer
 * 
 * @param tok Tokenizer handle
 * @param ids Token IDs to decode
 * @param ids_len Number of token IDs
 * @param out_text Output pointer to allocated buffer (caller must free with tokenizer_free_text)
 * @param out_len Output length of text
 * @return 0 on success, -1 on error
 */
int32_t tokenizer_decode_alloc(
    tokenizer_t tok,
    const int32_t* ids,
    size_t ids_len,
    char** out_text,
    size_t* out_len
);

/**
 * Free text buffer allocated by tokenizer_decode_alloc
 */
void tokenizer_free_text(char* text);

/**
 * Decode single token ID to text
 * 
 * @param tok Tokenizer handle
 * @param id Token ID
 * @param out_text Output buffer for text (caller allocated)
 * @param out_capacity Capacity of output buffer
 * @return Number of bytes written, or -1 on error
 */
int32_t tokenizer_id_to_token(
    tokenizer_t tok,
    int32_t id,
    char* out_text,
    size_t out_capacity
);

/* ═══════════════════════════════════════════════════════════════════════════
 * Metadata
 * ═══════════════════════════════════════════════════════════════════════════ */

/**
 * Get vocabulary size
 * 
 * @param tok Tokenizer handle
 * @return Vocabulary size, or 0 on error
 */
size_t tokenizer_vocab_size(tokenizer_t tok);

/**
 * Convert token string to ID
 * 
 * @param tok Tokenizer handle
 * @param token Token string
 * @param token_len Length of token string
 * @return Token ID, or -1 if not found
 */
int32_t tokenizer_token_to_id(
    tokenizer_t tok,
    const char* token,
    size_t token_len
);

#ifdef __cplusplus
}
#endif

#endif /* TOKENIZERS_C_H */
