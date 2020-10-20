#!/usr/bin/perl
#
# Copyright 2017   Ewald Enzinger
# Copyright 2019   Mickael Rouvier
# Apache 2.0
#
# Usage: data_prep.pl /export/data/cv_corpus_v1/cv-valid-train valid_train

if (@ARGV != 3) {
  print STDERR "Usage: $0 <path-to-commonvoice-corpus> <dataset> <valid-train|valid-dev|valid-test>\n";
  print STDERR "e.g. $0 /export/data/cv_corpus_v1 train train\n";
  exit(1);
}

($db_base, $dataset, $out_dir) = @ARGV;
mkdir data unless -d data;
mkdir $out_dir unless -d $out_dir;

open(TSV, "<", "$db_base/acoustic/$dataset.tsv") or die "cannot open dataset TSV file";
open(SPKR,">", "$out_dir/utt2spk") or die "Could not open the output file $out_dir/utt2spk";
open(GNDR,">", "$out_dir/utt2gender") or die "Could not open the output file $out_dir/utt2gender";
open(TEXT,">", "$out_dir/text") or die "Could not open the output file $out_dir/text";
open(WAV,">", "$out_dir/wav.scp") or die "Could not open the output file $out_dir/wav.scp";
#my $header = <TSV>;
while(<TSV>) {
  chomp;
  ($spkr, $filepath, $text, $upvotes, $downvotes, $age, $gender, $accent) = split("\t", $_);
  if ("$gender" eq "female") {
    $gender = "f";
  } else {
    # Use male as default if not provided (no reason, just adopting the same default as in voxforge)
    $gender = "m";
  }
  $uttId = $filepath;
  $uttId =~ s/\.mp3//g;
  $uttId =~ tr/\//-/;
  $uttId = "$spkr#$uttId";
  # No speaker information is provided, so we treat each utterance as coming from a different speaker
  print TEXT "$uttId"," ","$text","\n";
  print GNDR "$uttId"," ","$gender","\n";
  print WAV "$uttId"," sox $db_base/clips/$filepath -t wav -r 16k -b 16 -e signed - |\n";
  print SPKR "$uttId"," $spkr","\n";
}
close(SPKR) || die;
close(TEXT) || die;
close(WAV) || die;
close(GNDR) || die;
close(WAVLIST);

if (system(
  "utils/utt2spk_to_spk2utt.pl $out_dir/utt2spk >$out_dir/spk2utt") != 0) {
  die "Error creating spk2utt file in directory $out_dir";
}
system("env LC_COLLATE=C utils/fix_data_dir.sh $out_dir");
if (system("env LC_COLLATE=C utils/validate_data_dir.sh --no-feats $out_dir") != 0) {
  die "Error validating directory $out_dir";
}
