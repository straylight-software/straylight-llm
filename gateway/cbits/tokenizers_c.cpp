/*
 * C bindings for tokenizers-cpp
 */
#include "tokenizers_c.h"
#include <tokenizers_cpp.h>

#include <cstring>
#include <memory>
#include <vector>
#include <string>

struct TokenizerHandle {
    std::unique_ptr<tokenizers::Tokenizer> tok;
};

extern "C" {

tokenizer_t tokenizer_from_json(const char* json_data, size_t json_len) {
    try {
        std::string blob(json_data, json_len);
        auto tok = tokenizers::Tokenizer::FromBlobJSON(blob);
        if (!tok) return nullptr;
        
        auto handle = new TokenizerHandle();
        handle->tok = std::move(tok);
        return handle;
    } catch (...) {
        return nullptr;
    }
}

tokenizer_t tokenizer_from_sentencepiece(const char* model_data, size_t model_len) {
    try {
        std::string blob(model_data, model_len);
        auto tok = tokenizers::Tokenizer::FromBlobSentencePiece(blob);
        if (!tok) return nullptr;
        
        auto handle = new TokenizerHandle();
        handle->tok = std::move(tok);
        return handle;
    } catch (...) {
        return nullptr;
    }
}

void tokenizer_free(tokenizer_t tok) {
    delete tok;
}

int32_t tokenizer_encode(
    tokenizer_t tok,
    const char* text,
    size_t text_len,
    int32_t* out_ids,
    size_t out_capacity
) {
    if (!tok || !tok->tok) return -1;
    
    try {
        std::string input(text, text_len);
        auto ids = tok->tok->Encode(input);
        
        size_t count = ids.size();
        if (count <= out_capacity && out_ids) {
            std::memcpy(out_ids, ids.data(), count * sizeof(int32_t));
        }
        return static_cast<int32_t>(count);
    } catch (...) {
        return -1;
    }
}

int32_t tokenizer_encode_alloc(
    tokenizer_t tok,
    const char* text,
    size_t text_len,
    int32_t** out_ids,
    size_t* out_len
) {
    if (!tok || !tok->tok || !out_ids || !out_len) return -1;
    
    try {
        std::string input(text, text_len);
        auto ids = tok->tok->Encode(input);
        
        *out_len = ids.size();
        *out_ids = new int32_t[ids.size()];
        std::memcpy(*out_ids, ids.data(), ids.size() * sizeof(int32_t));
        return 0;
    } catch (...) {
        *out_ids = nullptr;
        *out_len = 0;
        return -1;
    }
}

void tokenizer_free_ids(int32_t* ids) {
    delete[] ids;
}

int32_t tokenizer_decode(
    tokenizer_t tok,
    const int32_t* ids,
    size_t ids_len,
    char* out_text,
    size_t out_capacity
) {
    if (!tok || !tok->tok) return -1;
    
    try {
        std::vector<int32_t> input(ids, ids + ids_len);
        auto text = tok->tok->Decode(input);
        
        size_t len = text.size();
        if (len < out_capacity && out_text) {
            std::memcpy(out_text, text.data(), len);
            out_text[len] = '\0';
        }
        return static_cast<int32_t>(len);
    } catch (...) {
        return -1;
    }
}

int32_t tokenizer_decode_alloc(
    tokenizer_t tok,
    const int32_t* ids,
    size_t ids_len,
    char** out_text,
    size_t* out_len
) {
    if (!tok || !tok->tok || !out_text || !out_len) return -1;
    
    try {
        std::vector<int32_t> input(ids, ids + ids_len);
        auto text = tok->tok->Decode(input);
        
        *out_len = text.size();
        *out_text = new char[text.size() + 1];
        std::memcpy(*out_text, text.data(), text.size());
        (*out_text)[text.size()] = '\0';
        return 0;
    } catch (...) {
        *out_text = nullptr;
        *out_len = 0;
        return -1;
    }
}

void tokenizer_free_text(char* text) {
    delete[] text;
}

int32_t tokenizer_id_to_token(
    tokenizer_t tok,
    int32_t id,
    char* out_text,
    size_t out_capacity
) {
    if (!tok || !tok->tok) return -1;
    
    try {
        auto text = tok->tok->IdToToken(id);
        size_t len = text.size();
        if (len < out_capacity && out_text) {
            std::memcpy(out_text, text.data(), len);
            out_text[len] = '\0';
        }
        return static_cast<int32_t>(len);
    } catch (...) {
        return -1;
    }
}

size_t tokenizer_vocab_size(tokenizer_t tok) {
    if (!tok || !tok->tok) return 0;
    
    try {
        return tok->tok->GetVocabSize();
    } catch (...) {
        return 0;
    }
}

int32_t tokenizer_token_to_id(
    tokenizer_t tok,
    const char* token,
    size_t token_len
) {
    if (!tok || !tok->tok) return -1;
    
    try {
        std::string input(token, token_len);
        return tok->tok->TokenToId(input);
    } catch (...) {
        return -1;
    }
}

} // extern "C"
