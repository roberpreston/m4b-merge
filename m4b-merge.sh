#!/bin/bash
# Script to use m4b-tool to merge audiobooks, easily.

INPUT="/home/$USER/Downloads/audiobooks"
TOMOVE="/home/$USER/Downloads/audiobooks/SORTING"
OUTPUT="/mnt/disk1/audiobooks"
DFLTSET="--ffmpeg-threads=8 --no-cache -v -d"
M4BPATH="/home/$USER/m4b-tool/m4b-tool.phar"

for dir in $INPUT/*
do
	if [[ $(find "$dir"/* -type f -regex ".*\.\(mp3\|m4b\)" | wc -l) -gt 1 ]]; then
		#echo "Found dir with more than one audiobook file: "$(basename "$dir")""
		echo "$(basename "$dir")" >> "$INPUT"/abook
		#echo -e ' \n ' >> "$INPUT"/abook
	fi
done

IFS=$'\n'
select adbook in $(cat $INPUT/abook) exit; do
  case "$adbook" in
      exit) echo "exiting"
            break ;;
         *) read -e -p 'Enter name: ' namevar
		 	read -e -p 'Enter Albumname: ' albumvar
		 	read -e -p 'Enter artist (Narrator): ' artistvar
		 	read -e -p 'Enter albumartist (Author): ' albumartistvar
			read -e -p 'Enter bitrate, if any: ' brvar
		 	echo "Starting conversion of $adbook..."
		 	mkdir -p "$TOMOVE"/"$artistvar"/"$albumvar"
			php "$M4BPATH" merge "$INPUT"/"$adbook" --output-file="$TOMOVE"/"$artistvar"/"$albumvar"/"$namevar".m4b --name=$namevar --album=$albumvar --artist=$artistvar --albumartist=$albumartistvar --audio-bitrate=$brvar $DFLTSET
			echo "Done."
			;;
  esac
done

rm "$INPUT"/abook

exec screen -dmS rclonesorted rclone move "$TOMOVE" "$OUTPUT" --transfers=1 --verbose --stats 20s