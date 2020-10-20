#!/bin/bash

# Recipe for Mozilla LIA Common Voice corpus v1
#
# Copyright 2017   Ewald Enzinger
# Copyright 2019   Mickael Rouvier
# Apache 2.0

. ./cmd.sh
. ./path.sh

stage=7
nj=30

. ./utils/parse_options.sh

set -euo pipefail

if [ $stage -le 0 ]; then
  local/download_and_untar.sh
fi

if [ $stage -le 1 ]; then
  for part in train dev test; do
    local/data_prep.pl db/lia_commonvoice/ $part data/$part
  done
  
  # Prepare ARPA LM and vocabulary using SRILM
  local/prepare_lm.sh data/train

  # Prepare the lexicon and various phone lists
  # Pronunciations for OOV words are obtained using a pre-trained Sequitur model
  local/prepare_dict.sh

  # Prepare data/lang and data/local/lang directories
  utils/prepare_lang.sh data/local/dict '<unk>' data/local/lang data/lang || exit 1

  local/arpatofsm.sh  data/lang db/lia_commonvoice/language/lm.gz db/lia_commonvoice/language/lexicon.txt data/lang_test/
  #utils/format_lm.sh data/lang db/lia_commonvoice/language/lm.gz db/lia_commonvoice/language/lexicon.txt data/lang_test
  
fi


if [ $stage -le 2 ]; then
  mfccdir=mfcc
  for part in train dev test; do
    steps/make_mfcc.sh --cmd "$train_cmd" --nj $nj data/$part exp/make_mfcc/$part $mfccdir
    steps/compute_cmvn_stats.sh data/$part exp/make_mfcc/$part $mfccdir
  done

  # Get the shortest 10000 utterances first because those are more likely
  # to have accurate alignments.
  utils/subset_data_dir.sh --shortest data/train 10000 data/train_10kshort || exit 1;
  utils/subset_data_dir.sh data/train 20000 data/train_20k || exit 1;
fi

# train a monophone system
if [ $stage -le 3 ]; then
  steps/train_mono.sh --boost-silence 1.25 --nj $nj --cmd "$train_cmd" \
    data/train_10kshort data/lang exp/mono || exit 1;

  steps/align_si.sh --boost-silence 1.25 --nj $nj --cmd "$train_cmd" \
    data/train_20k data/lang exp/mono exp/mono_ali_train_20k
fi

# train a first delta + delta-delta triphone system
if [ $stage -le 4 ]; then
  steps/train_deltas.sh --boost-silence 1.25 --cmd "$train_cmd" \
    2000 10000 data/train_20k data/lang exp/mono_ali_train_20k exp/tri1

  steps/align_si.sh --nj $nj --cmd "$train_cmd" \
    data/train_20k data/lang exp/tri1 exp/tri1_ali_train_20k
fi

# train an LDA+MLLT system.
if [ $stage -le 5 ]; then
  steps/train_lda_mllt.sh --cmd "$train_cmd" \
    --splice-opts "--left-context=3 --right-context=3" 2500 15000 \
    data/train_20k data/lang exp/tri1_ali_train_20k exp/tri2b

  # Align utts using the tri2b model
  steps/align_si.sh --nj $nj --cmd "$train_cmd" --use-graphs true \
    data/train_20k data/lang exp/tri2b exp/tri2b_ali_train_20k
fi

# Train tri3b, which is LDA+MLLT+SAT
if [ $stage -le 6 ]; then
  steps/train_sat.sh --cmd "$train_cmd" 2500 15000 \
    data/train_20k data/lang exp/tri2b_ali_train_20k exp/tri3b
fi

if [ $stage -le 7 ]; then
  # Align utts in the full training set using the tri3b model
  steps/align_fmllr.sh --nj $nj --cmd "$train_cmd" \
    data/train data/lang \
    exp/tri3b exp/tri3b_ali_train

  # train another LDA+MLLT+SAT system on the entire training set
  steps/train_sat.sh  --cmd "$train_cmd" 4200 40000 \
    data/train data/lang \
    exp/tri3b_ali_train exp/tri4b

fi

# Train a chain model
if [ $stage -le 8 ]; then
  local/chain/run_tdnn.sh --stage 0
fi

# Don't finish until all background decoding jobs are finished.
wait
