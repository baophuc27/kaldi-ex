#!/bin/bash

. ./path.sh || exit 1
. ./cmd.sh || exit 1

nj=16        # number of parallel jobs
lm_order=5    # language  model order (1 for unigram, 2 for bigram,...)
mfcc_folder=mfcc

# set -euo pipefail
set +e
# Safety mechanism (possible running this script with modified arguments)

. utils/parse_options.sh 
stage=$1
# Removing previously created data (from last run.sh execution)
rm -rf exp mfcc data/train/spk2utt data/train/cmvn.scp data/train/feats.scp data/train/split1 data/test/spk2utt data/test/cmvn.scp data/test/feats.scp data/test/split1 data/local/tmp

if [ $stage -le 0 ]; then
    echo ""
    echo "=========================================="
    echo "======== DOWNLOAD & UNTAR DATA ==========="
    echo "=========================================="
    echo ""
    data_url=https://ailab.hcmus.edu.vn/assets/vivos.tar.gz
    wget_script=local/download_and_untar_vivos.sh

    chmod +x $wget_script
    $wget_script data $data_url
fi


if [ $stage -le 1 ]; then
    echo ""
    echo "=========================================="
    echo "======= PREPARING ACOUSTIC DATA =========="
    echo "=========================================="
    echo ""

    # Create spk2gender, wav.scp, text, utt2spk, corpus.txt, spk2utt
    python3 local/prepare_data.py --raw-dir data/vivos --processed-dir data

    # Make spk2utt from utt2spk
    utils/utt2spk_to_spk2utt.pl data/train/utt2spk > data/train/spk2utt
    utils/utt2spk_to_spk2utt.pl data/test/utt2spk > data/test/spk2utt


    mfcc_dir=`pwd`/mfcc
    # # Make MFCC features
    for x in train test; do 
        steps/make_mfcc.sh --cmd "$train_cmd" --nj "$nj"  data/$x exp/make_mfcc/$x $mfcc_dir
        # Cepstral mean variance normalization
        steps/compute_cmvn_stats.sh data/$x exp/make_mfcc/$x $mfcc_dir
        utils/fix_data_dir.sh data/$x
    done
fi

if [ $stage -le 2 ]; then
    echo ""
    echo "=========================================="
    echo "======= PREPARING LANGUAGE DATA =========="
    echo "=========================================="
    echo ""

    # Prepare lexicon.txt, nonsilence_phones.txt, optional_silence.txt, silence_phones.txt

    # Use utils/prepare_lang.sh to generate all files in data/lang
    # Usage: utils/prepare_lang.sh <dict-src-dir> <oov-dict-entry> <tmp-dir> <lang-dir>
    utils/prepare_lang.sh data/local/lang "<UNK>" data/local data/lang
fi

if [ $stage -le 3 ]; then
    echo ""
    echo "=========================================="
    echo "======== MAKING LANGUAGE MODEL ==========="
    echo "=========================================="
    echo ""

    loc=`which ngram-count`;

    if [ -z $loc ]; then
        if uname -a | grep 64 >/dev/null; then
                sdir=$KALDI_ROOT/tools/srilm/bin/i686-m64
        else
                        sdir=$KALDI_ROOT/tools/srilm/bin/i686
        fi

        if [ -f $sdir/ngram-count ]; then
                        echo "Using SRILM language modelling tool from $sdir"
                        export PATH=$PATH:$sdir
        else
                        echo "SRILM toolkit is probably not installed.
                                Instructions: tools/install_srilm.sh"
                        exit 1
        fi
    fi
    local=data/local
    mkdir $local/tmp
    ngram-count -order $lm_order -write-vocab $local/tmp/vocab-full.txt -wbdiscount -text $local/corpus.txt -lm $local/tmp/lm.arpa


    # Making G.fst
    lang=data/lang
    arpa2fst --disambig-symbol=#0 --read-symbol-table=$lang/words.txt $local/tmp/lm.arpa $lang/G.fst
fi


if [ $stage -le 4 ]; then
    echo ""
    echo "=========================================="
    echo "== MONOPHONE TRAINING, DECODING, ALIGN ==="
    echo "=========================================="
    echo ""

    # Training monophone
    # Usage: steps/train_mono.sh [options] <data-dir> <lang-dir> <exp-dir>
    steps/train_mono.sh --nj "$nj" --cmd "$train_cmd" data/train data/lang exp/mono


fi

if [ $stage -le 5 ]; then
    echo ""
    echo "==========================================="
    echo "======== MONO DECODE AND ALIGN ============"
    echo "==========================================="
    echo ""

    # Decoding
    utils/mkgraph.sh --mono data/lang exp/mono exp/mono/graph

    # Align
    steps/align_si.sh --nj $nj --cmd "$train_cmd" \
        data/train data/lang exp/mono exp/mono_ali
fi

if [ $stage -le 6 ]; then
    echo ""
    echo "==========================================="
    echo "=========== TRIPHONE TRAINING ============="
    echo "==========================================="
    echo ""
    # Triphone training with 2500 HMM states and 20000 GMM

    steps/train_deltas.sh --cmd "$train_cmd" 2500 20000 \
    data/train data/lang exp/mono_ali exp/tri1
fi

if [ $stage -le 7 ]; then
    echo ""
    echo "==========================================="
    echo "============= TRI1 DECODING  =============="
    echo "==========================================="
    echo ""

    utils/mkgraph.sh data/lang exp/tri1 exp/tri1/graph || exit 1

    echo ""
    echo "==========================================="
    echo "============= TRI1 ALIGNMENT  ============="
    echo "==========================================="
    echo ""

    steps/align_si.sh --nj $nj --cmd "$train_cmd" \
    data/train data/lang exp/tri1 exp/tri1_ali ;
fi


if [ $stage -le 8 ]; then
    echo ""
    echo "==========================================="
    echo "=========== TRIPHONE2 TRAINING ============"
    echo "==========================================="
    echo ""

    steps/train_deltas.sh --cmd "$train_cmd" 2500 20000 \
    data/train data/lang exp/tri1_ali exp/tri2a 

    echo ""
    echo "==========================================="
    echo "============= TRI2 DECODING  =============="
    echo "==========================================="
    echo ""

    utils/mkgraph.sh data/lang exp/tri2a exp/tri2a/graph 

    # Decoding
    chmod +x local/score.sh
    steps/decode.sh --nj $nj --cmd "$decode_cmd" \
    exp/tri2a/graph data/test exp/tri2a/decode

    echo ""
    echo "==========================================="
    echo "============= TRI2 ALIGNMENT  ============="
    echo "==========================================="
    echo ""
    steps/align_si.sh --nj $nj --cmd "$train_cmd" \
    data/train data/lang exp/tri2a exp/tri2a_ali 

fi

