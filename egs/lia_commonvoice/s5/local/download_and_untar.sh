#!/bin/bash

# Copyright  2014  Nickolay V. Shmyrev
#            2014  Brno University of Technology (Author: Karel Vesely)
#            2016  John Hopkins University (author: Daniel Povey)
#            2019  Mickael Rouvier
# Apache 2.0

mkdir -p db

cd db  ### Note: the rest of this script is executed from the directory 'db'.

# TED-LIUM database:
if [ ! -e TEDLIUM_release-3 ]; then
  echo "$0: downloading TEDLIUM_release-3 data (it won't re-download if it was already downloaded.)"
  # the following command won't re-get it if it's already there
  # because of the --continue switch.
  wget --continue http://mickael-rouvier.fr/ressources/db/lia_commonvoice.tar.gz || exit 1

  echo "$0: extracting corpus data"
  tar xf "lia_commonvoice.tar.gz"

else
  echo "$0: not downloading or un-tarring data because it already exists."
fi


cd ..

exit 0
