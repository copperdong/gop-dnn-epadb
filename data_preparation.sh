#!/bin/sh

set -x

echo "preparing epadb directories"

ln -s ../wsj/s5/steps .
ln -s ../wsj/s5/utils .
ln -s ../../src .


# The script takes the corpus directory with .wav and .lab files and prepares data for gop-dnn computation with kaldi.
# You should expect to have wav.scp, utt2spk, spk2utt and text file in data/test folder.

data='corpus'
dir='data/test_epa'
mkdir -p $dir

echo 'Preparing data dirs'
for d in $data/*; do
    #echo $d
    for f in $d/*.wav; do
        filename="$(basename $f)"
        filepath="$(dirname $f)"
        spkname="$(basename $filepath)"
        echo "${filename%.*} $filepath/$filename" >> $dir/wav.scp # Prepare wav.scp
        echo "$spkname ${filename%.*}" >> $dir/spk2utt # Prepare spk2utt
        echo "${filename%.*} $spkname" >> $dir/utt2spk # Prepare utt2spk
        (
            printf "${filename%.*} "
            cat "$data/$spkname/${filename%.*}.lab" | tr [a-z] [A-Z]
            printf "\n"
        ) >> $dir/text # Prepare transcript
    done
done

utils/fix_data_dir.sh $dir

# wav-to-duration --read-entire-file=true p,scp:$dir/wav.scp ark,t:$dir/utt2dur || exit 1; # Prepare utt2dur

# Download language model and acoustic model from Kaldi. For more details see: https://kaldi-asr.org/models/m13

echo 'Downloading models from Kaldi'
[ ! -f 0013_librispeech_s5.tar.gz ] &&  wget https://kaldi-asr.org/models/13/0013_librispeech_s5.tar.gz
[ ! -d 0013_librispeech_v1 ] &&  tar -zxvf 0013_librispeech_s5.tar.gz

# Move folders to the corresponding directories
cp -r 0013_librispeech_v1/exp/chain_cleaned/tdnn_1d_sp exp/nnet3_cleaned
cp -r 0013_librispeech_v1/exp/nnet3_cleaned/extractor exp/nnet3_cleaned
cp -r 0013_librispeech_v1/data/lang_chain data/


# feature extraction
utils/copy_data_dir.sh data/test_epa data/test_epa_hires

echo "Extracting features for DNN model!"
steps/make_mfcc.sh --nj 8 --mfcc-config conf/mfcc_hires.conf --cmd "run.pl" data/test_epa_hires
steps/compute_cmvn_stats.sh data/test_epa_hires
utils/fix_data_dir.sh data/test_epa_hires


# Extract ivectors
nspk=$(wc -l <data/test_epa_hires/spk2utt)
steps/online/nnet2/extract_ivectors_online.sh --cmd "run.pl" --nj "${nspk}" data/test_epa_hires exp/nnet3_cleaned/extractor exp/nnet3_cleaned/ivectors_test_epa_hires

echo "Finish data preparation and feature extraction!"

#echo "prepareing GOP directories" # Quizas esta parte deberia estar en el run.sh

gop_dir='../gop/s5'
mkdir $gop_dir/exp
mkdir $gop_dir/data
cp -r data/test_epa_hires $gop_dir/data/
mv $gop_dir/data/test_epa_hires $gop_dir/data/test_epa
