#!/bin/zsh

# Creates folder structure as it is on the reMarkable 2
# from a local raw file backup.
#
# - thumbnails are copied and named in page order (1.jpg, 2.jpg etc.)
# - trashed files go to a _trash directory
# optional:
# - favorites are prefixed with "* "
# - version numbers of cloud-synced files are suffixed, e.g. "(v10)"
# - files with sync status deleted are suffixed " (deleted)"
# - macOS only: notebook folders get a nice icon to separate them from folder folders   
#
# u/RedTartan04 02/02/2022
#

# Inspired by Kim Covil 
# https://github.com/arnoxit/remarkable/blob/master/scripts/file-tree

# Flags
PROGRESS=1
VERBOSE=
DEBUG=
addDeletedState=1
addVersion=
# macOs only
addIcon=1

# Paths
## Do not enclose a path with ~ in "", otherwise the ~ is not expanded 
# do not end with a /
srcDir=~/Documents/reMarkable/_rsync_backup/xochitl
tgtDir=~/Documents/reMarkable/_rsync_backup/file-tree

# Where the Icon.rsrc file for the notebook's folder icon is found
# (to get a folder's icon resource file:
#  DeRez -only icns ./Icon$'\r' > Icon.rsrc)
[[ -n "${addIcon}" ]] && iconDir=~/Documents/reMarkable/_Icons/notebook

# Variables
# associative arrays (key, value)
typeset -A PARENT
typeset -A NAME
typeset -A TYPE
typeset -A FULL
typeset -A META_FAVS
typeset -A META_DELS
typeset -A META_VERS
typeset -A FOLDERS
# numerical-indexed arrays
typeset -a FILES
#typeset -a DIRS
typeset -a PAGEIDS

# cleanup target dir
rm -fR ${tgtDir}/*
mkdir -p "${tgtDir}/_trash"

echo
echo "Copying from " $srcDir 
echo "        to   " $tgtDir
echo

echo "Getting metadata..."
for D in "${srcDir}/"*.metadata; do

    UUID="$(basename "${D}" ".metadata")"
    PARENT["${UUID}"]="$(awk -F\" '$2=="parent"{print $4}' "${D}")"
    TYPE["${UUID}"]="$(awk -F\" '$2=="type"{print $4}' "${D}")"
    NAME["${UUID}"]="$(awk -F\" '$2=="visibleName"{print $4}' "${D}")"

	# replace / in name by : for mac file system
	# (: in filesystem will appear as / in Finder)
	NAME["${UUID}"]=${${NAME["${UUID}"]}//\//:}
	
	# names beginning with . are prefixed with a space
	# so they wont be invisible in Finder
	NAME["${UUID}"]=${${NAME["${UUID}"]}//./ .}

    # awk results in ': false,' so we cut off ': ' and ','
    META_FAVS["${UUID}"]="$(awk -F\" '$2=="pinned"{print $3}' "${D}" | cut -d ' ' -f2 | cut -d , -f1)"
    META_DELS["${UUID}"]="$(awk -F\" '$2=="deleted"{print $3}' "${D}" | cut -d ' ' -f2 | cut -d , -f1)"
    META_VERS["${UUID}"]="$(awk -F\" '$2=="version"{print $3}' "${D}" | cut -d ' ' -f2 | cut -d , -f1)"
    
    if [[ "${TYPE["${UUID}"]}" == "DocumentType" ]] then
        FILES+=( "${UUID}" )
       	[[ -n "${PROGRESS}" ]] && echo -n "."
    elif [[ "${TYPE["${UUID}"]}" == "CollectionType" ]] then
    # not used
    #    DIRS+=( "${UUID}" )
    #	[[ -n "${PROGRESS}" ]] && echo -n "/"
    else
        echo "WARN: UUID ${UUID} has an unknown type ${TYPE["${UUID}"]}" >&2
    fi
done
[[ -n "${PROGRESS}" ]] && echo ""

echo "Creating file tree..."

for F in "${FILES[@]}"; do
	[[ -n "${PROGRESS}" ]] && echo -n "."

    FULL["${F}"]="${NAME["${F}"]}"
    P="${PARENT["${F}"]}"
    declare -i folderDepth=0
    #prefix parent dirs to full name
    while [[ "${P}" != "" ]]; do
    	[[ -n "${DEBUG}" ]] && echo "p name: " ${NAME["${P}"]}
		folderDepth+=1
		
		#** handle name
		if (( folderDepth == 1 )) then
			
			# handle some metadata

			# favorite (pinned)
			[[ -n "${DEBUG}" ]] && echo "fav: " ${META_FAVS["${F}"]}
			if [[ "${META_FAVS["${F}"]}" == "true" ]] then
				# prefix name with '* '
				FULL["${F}"]="* ${FULL["$F"]}"        	
			fi
			
			# deleted
			if [[ -n "${addDeletedState}" ]] then
				[[ -n "${DEBUG}" ]] && echo "del: " ${META_DELS["${F}"]}
				if [[ "${META_DELS["${F}"]}" == "true" ]] then
					# suffix name
					FULL["${F}"]="${FULL["$F"]} (deleted)"        	
				fi
			fi

			# version (print only if not 0)
			if [[ -n "${addVersion}" ]] then
				[[ -n "${DEBUG}" ]] && echo "del: " ${META_VERS["${F}"]}
				if [[ "${META_VERS["${F}"]}" != "0" ]] then
					# suffix name
					FULL["${F}"]="${FULL["$F"]} (v${META_VERS["${F}"]})"        	
				fi
			fi

		fi

        #** handle location
        
        # if parent's id is trash
        if [[ "${P}" == "trash" ]] then
        	# put file in trash dir
           	FULL["${F}"]="_trash/${FULL["$F"]}"
	       	break
	    fi
	    
    	# if parent not empty (?)
        if [[ -n "${FULL["${P}"]}" ]] then
        	#prepend parent's path
        	FULL["${F}"]="${FULL["${P}"]}/${FULL["$F"]}"
           	break
        else
        	#prepend parent's name (why?)
            FULL["${F}"]="${NAME["${P}"]}/${FULL["$F"]}"
        fi

		# step up one level in dir hierarchy
        P="${PARENT["${P}"]}"
    done

	# if parent not empty
    P=${PARENT["${F}"]}
    if [[ -n "${PARENT["${F}"]}" && -z "${FULL["${P}"]}" ]] then
        FULL["${xPARENT}"]="$(dirname "${FULL["${F}"]}")"
    fi

    TARGET="${FULL["${F}"]}"

    [[ -n "${VERBOSE}" ]] && echo "UUID ${F} -> ${TARGET}"
    
    # create folder dir
    mkdir -p "${tgtDir}/$(dirname "${TARGET}")"
    # store for later (ass. array to remove duplicates)
	#FOLDERS+=( "${tgtDir}/$(dirname "${TARGET}")" "${tgtDir}/$(dirname "${TARGET}")" )
	FOLDERS+=( "${tgtDir}/$(dirname "${TARGET}")" $folderDepth )

	# -e exists -f file exists? -d dir exists?
    if [[ ! "${srcDir}/${F}.thumbnails" -ef "${tgtDir}/${TARGET}" ]] then
    	[[ -n "${DEBUG}" ]] && echo "Linking ${srcDir}/${F}\n     to ${tgtDir}/${TARGET}"
	
		# link the source uuid.thumbnails DIR to book name    
        #ln -s "${srcDir}/${F}.thumbnails" "${tgtDir}/${TARGET}"
        
        # instead create dir for book...
        mkdir -p "${tgtDir}/${TARGET}"

        # ...and (soft) link all files in .thumbnails into it
        #ln -s "${srcDir}/${F}.thumbnails/"* "${tgtDir}/${TARGET}"
        
        # ...or number thumbnail links to their corresponding page number
        
        # get list of page ids; first is page 1 etc.
        [[ -n "${PROGRESS}" ]] && echo -n "x\b"
        PAGEIDS=()
        inPageList=
		currentPageId=
		while read -r line; do
			#store page id
			if [[ $inPageList == "true" ]] 
			then
				# find end of page id list
				[[ $line == "]," ]] && break 
		
				# one UUID per line, remove comma
				currentPageId=$(echo $line | cut -d , -f1)
				PAGEIDS=("${PAGEIDS[@]}" $currentPageId)
			fi
			# find start of page id list
			[[ $line == *pages* ]] && inPageList="true"
		done < "${srcDir}/${F}.content"
		[[ -n "${DEBUG}" ]] && typeset -p PAGEIDS # print the array
		
		# format page number with leading zeros as needed
		numPages=$#PAGEIDS
		numDigits=${#numPages}
		pNumFormat="%0"$numDigits"d"
		if [[ -n "${DEBUG}" ]] then
			echo "size: " $#PAGEIDS
			echo "digits:" $numDigits
			echo "pNumFormat: " $pNumFormat
		fi
		
		# iterate over all page id and create links with page number as name
		[[ -n "${PROGRESS}" ]] && echo -n "+\b"
		for i in {1..$numPages}; do
			# formatted page number
			pageNumFileName=$(printf $pNumFormat $i)

			# UUID of page
			pageId=$PAGEIDS[i]
			# strip off "
			pageId="${pageId%\"}"
			pageId="${pageId#\"}"
			
			[[ -n "${DEBUG}" ]] && echo $pageNumFileName: $pageId
			
			# link jpg thumbnail files
			if [[ -e "${srcDir}/${F}.thumbnails/${pageId}.jpg" ]] then
				# HARD links provide icon preview in Finder (and not appear as generic alias icon)
				# cave: they look like copies but if deleted, the original is deleted, too!
				# (removing w flag, also makes original read only) 
				#ln -f "${srcDir}/${F}.thumbnails/${pageId}.jpg" "${tgtDir}/${TARGET}/${pageNumFileName}.jpg"
				
				# copy instead of hard linking (small files, fast with APFS anyway)
				# that copy may be changed without affecting original
				# (-p preserves timestamp, etc.)
				cp -p "${srcDir}/${F}.thumbnails/${pageId}.jpg" "${tgtDir}/${TARGET}/${pageNumFileName}.jpg"
				
			else
				# there may be ids in the list but no jpg file for it :-/
				#ln -s "${srcDir}/${F}.thumbnails/${pageId}.jpg" "${tgtDir}/${TARGET}/${pageNumFileName}_.jpg"			
			fi
		done

		# macOS:set notebook's Finder icon
        if [[ -n "${addIcon}" ]] then
			# assign icon to folder
			Rez -a "${iconDir}"/Icon.rsrc -o "${tgtDir}/${TARGET}"/Icon$'\r'
			# show this icon resource as custom folder icon
			SetFile -a C "${tgtDir}/${TARGET}"
			# hide the actual Icon file from Finder
			SetFile -a V "${tgtDir}/${TARGET}"/Icon$'\r'
		fi

		# after done with the book,

        # set its dir date to the date of the .thumbnail dir
        # this should be the 'last modified' date
        touch -r "${srcDir}/${F}.thumbnails" "${tgtDir}/${TARGET}"

    fi
done
	
# after done completely, set date of folder dirs
# to newest date of subdirs, (to be able to sort in Finder)

if [[ -n "${DEBUG}" ]] then
	echo "\nfolder - depth"
	for folder depth in "${(@kv)FOLDERS}"; do
		echo $folder - $depth
	done
fi

# we have to modify the deepest dirs first,
# because that updates the modified date of its parent

# iterate over reverse sorted values (= depths)
typeset -A currentFolders
lastDepth=-1
for depth ("${(@nO)FOLDERS}"); do

	# if we have reached the top level, we're done
	# (don't change the date of the target tree dir itself)
	if [[ $depth == "0" ]] then
		break
	fi
	
	# do this only once per depth value
	if [[ $depth != $lastDepth ]] then

		# get list of keys (= folders), matching current value (= depth)
		currentFolders=("${(@kv)FOLDERS[(eR)$depth]}")
	
		# iterate over folders (= keys of currentFolders)
		for folder in "${(@k)currentFolders}"; do
  			[[ -n "${DEBUG}" ]] && echo "$folder -> $currentFolders[$folder]"
  			
  			# set date of dir to newest date of subdirs
			touch -r $folder/*(om[1]) $folder
		done
	
		lastDepth=$depth
	fi
done

[[ -n "${PROGRESS}" ]] && echo "."

