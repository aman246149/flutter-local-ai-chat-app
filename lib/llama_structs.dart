import 'dart:ffi';

// Configuration object matching llama_model_params in llama.h
base class LlamaModelParams extends Struct {
  external Pointer<Void> devices;
  external Pointer<Void> tensor_buft_overrides;

  @Int32()
  external int n_gpu_layers;

  @Int32()
  external int split_mode;

  @Int32()
  external int main_gpu;

  external Pointer<Float> tensor_split;

  external Pointer<Void> progress_callback;
  external Pointer<Void> progress_callback_user_data;
  external Pointer<Void> kv_overrides;

  @Bool()
  external bool vocab_only;
  @Bool()
  external bool use_mmap;
  @Bool()
  external bool use_mlock;
  @Bool()
  external bool check_tensors;
  @Bool()
  external bool use_extra_bufts;
  @Bool()
  external bool no_host;
  @Bool()
  external bool no_alloc;
}

// Matching llama_context_params in llama.h
base class LlamaContextParams extends Struct {
  @Uint32()
  external int n_ctx;
  @Uint32()
  external int n_batch;
  @Uint32()
  external int n_ubatch;
  @Uint32()
  external int n_seq_max;
  @Int32()
  external int n_threads;
  @Int32()
  external int n_threads_batch;

  @Int32()
  external int rope_scaling_type;
  @Int32()
  external int pooling_type;
  @Int32()
  external int attention_type;
  @Int32()
  external int flash_attn_type;

  @Float()
  external double rope_freq_base;
  @Float()
  external double rope_freq_scale;
  @Float()
  external double yarn_ext_factor;
  @Float()
  external double yarn_attn_factor;
  @Float()
  external double yarn_beta_fast;
  @Float()
  external double yarn_beta_slow;
  @Uint32()
  external int yarn_orig_ctx;
  @Float()
  external double defrag_thold;

  external Pointer<Void> cb_eval;
  external Pointer<Void> cb_eval_user_data;

  @Int32()
  external int type_k;
  @Int32()
  external int type_v;

  external Pointer<Void> abort_callback;
  external Pointer<Void> abort_callback_data;

  @Bool()
  external bool embeddings;
  @Bool()
  external bool offload_kqv;
  @Bool()
  external bool no_perf;
  @Bool()
  external bool op_offload;
  @Bool()
  external bool swa_full;
  @Bool()
  external bool kv_unified;
}

// Matching llama_batch in llama.h
base class LlamaBatch extends Struct {
  @Int32()
  external int n_tokens;

  external Pointer<Int32> token;
  external Pointer<Float> embd;
  external Pointer<Int32> pos;
  external Pointer<Int32> n_seq_id;
  external Pointer<Pointer<Int32>> seq_id;
  external Pointer<Int8> logits; // int8_t *
}

// Matching llama_token_data
base class LlamaTokenData extends Struct {
  @Int32()
  external int id;
  @Float()
  external double logit;
  @Float()
  external double p;
}

// Matching llama_token_data_array
base class LlamaTokenDataArray extends Struct {
  external Pointer<LlamaTokenData> data;
  @Size()
  external int size;
  @Int64()
  external int selected;
  @Bool()
  external bool sorted;
}
