#!/usr/bin/env bash

# Copyright 2019 Mickael Rouvier

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
# WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
# MERCHANTABLITY OR NON-INFRINGEMENT.
# See the Apache 2 License for the specific language governing permissions and
# limitations under the License.

set -e

if [ $# -ne 4 ]; then
  echo "Usage: $0 <lang_dir> <arpa-LM> <lexicon> <out_dir>"
  echo "E.g.: $0 data/lang data/local/lm/foo.kn.gz data/local/dict/lexicon.txt data/lang_test"
  echo "Convert ARPA-format language models to FSTs.";
  exit 1;
fi

silprob=0.5
silphone="SIL"

lang_dir=$1
grammar=$2
lexicon_file=$3
out_dir=$4


if [ -f path.sh ]; then . path.sh; fi

export LC_ALL=en_US.UTF-8

export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8
export LC_ALL=en_US.UTF-8



cp -r $lang_dir $out_dir

(echo "<sil> SIL";) | cat - ${lexicon_file} > $out_dir/lexicon.txt

perl -ane '@A=split(" ",$_); $w = shift @A; @A>0||die;                                                                                                                             
           if(@A==1) { print "$w $A[0]_S\n"; } else { print "$w $A[0]_B ";                                                                                                             
           for($n=1;$n<@A-1;$n++) { print "$A[$n]_I "; } print "$A[$n]_E\n"; } ' < $out_dir/lexicon.txt > $out_dir/lexicon1.txt

utils/add_lex_disambig.pl $out_dir/lexicon1.txt $out_dir/lexicon_disambig.txt

cat $out_dir/lexicon1.txt | awk '{print $1}' | sort | uniq  | \
    awk 'BEGIN{print "<eps> 0";} {printf("%s %d\n", $1, NR);} END{printf("#0 %d\n", NR+1); printf("<s> %d\n", NR+2); printf("</s> %d\n", NR+3);} ' \
  > $out_dir/words.txt 


ndisambig=`utils/add_lex_disambig.pl $out_dir/lexicon1.txt $out_dir/lexicon_disambig.txt`
ndisambig=$[$ndisambig+1]; 

phone_disambig_symbol=`grep \#0 $out_dir/phones.txt | awk '{print $2}'`
word_disambig_symbol=`grep \#0 $out_dir/words.txt | awk '{print $2}'`

echo $phone_disambig_symbol
echo $word_disambig_symbol

cat $out_dir/words.txt | grep "<unk>" | cut -f2 -d" " > $out_dir/oov.int


utils/make_lexicon_fst.pl $out_dir/lexicon_disambig.txt $silprob $silphone '#'$ndisambig | fstcompile --isymbols=$out_dir/phones.txt --osymbols=$out_dir/words.txt --keep_isymbols=false --keep_osymbols=false | fstaddselfloops  "echo $phone_disambig_symbol |" "echo $word_disambig_symbol |" | fstarcsort --sort_type=olabel > $out_dir/L_disambig.fst


cat $grammar | \
   utils/eps2disambig.pl | utils/s2eps.pl | fstcompile --isymbols=$out_dir/words.txt \
     --osymbols=$out_dir/words.txt  --keep_isymbols=false --keep_osymbols=false | \
    fstrmepsilon > $out_dir/G.fst
  fstisstochastic $out_dir/G.fst


echo  "Checking how stochastic G is (the first of these numbers should be small):"
fstisstochastic $out_dir/G.fst 

## Check lexicon.
## just have a look and make sure it seems sane.
cat $out_dir/lexicon1.txt | ruby lexiconp.rb > $out_dir/lexiconp.txt
utils/make_lexicon_fst.pl --pron-probs $out_dir/lexiconp.txt $silprob $silphone | \
    fstcompile --isymbols=$out_dir/phones.txt --osymbols=$out_dir/words.txt \
    --keep_isymbols=false --keep_osymbols=false | \
    fstarcsort --sort_type=olabel > $out_dir/L.fst

echo "First few lines of lexicon FST:"
fstprint   --isymbols=$out_dir/phones.txt --osymbols=$out_dir/words.txt $out_dir/L.fst  | head

echo Performing further checks

# Checking that G.fst is determinizable.
fstdeterminize $out_dir/G.fst /dev/null || echo Error determinizing G.

# Checking that L_disambig.fst is determinizable.
fstdeterminize $out_dir/L_disambig.fst /dev/null || echo Error determinizing L.

# Checking that disambiguated lexicon times G is determinizable
# Note: we do this with fstdeterminizestar not fstdeterminize, as
# fstdeterminize was taking forever (presumbaly relates to a bug
# in this version of OpenFst that makes determinization slow for
# some case).
fsttablecompose $out_dir/L_disambig.fst $out_dir/G.fst | \
   fstdeterminizestar >/dev/null || echo Error

# Checking that LG is stochastic:
fsttablecompose $out_dir/L_disambig.fst $out_dir/G.fst | \
   fstisstochastic || echo LG is not stochastic


echo "succeeded."

