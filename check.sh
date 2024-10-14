#!/bin/bash -Eeu

log() {
	echo 2>&1 "${@}"
}

log_clearable() {
	local prefix
	prefix="$1 "
	shift
	local available_chars
	available_chars=$(( $(tput cols) - ${#prefix} ))
	local suffix
	suffix="$(echo "${@}")"
	if (( ${#suffix} > available_chars ))
	then
		local ellipsis
		ellipsis="[...]"
		available_chars=$(( available_chars - ${#ellipsis} ))
		suffix="$ellipsis$(echo "$suffix" | tail -c $available_chars)"
	fi
	tput sc
	log -n "$prefix$suffix"
}

log_clear() {
	tput el1 rc
}

usage() {
	log "Usage:   $0 <java home> <version-including-.Final-if-relevant> [file-to-diff]"
}

diff_silent() {
	diff -q 1>/dev/null "${@}"
}

diff_patch() {
	diff "${@}"
}

if (( $# < 2 )) || (( $# > 3 ))
then
	log "Wrong number of arguments"
	usage
	exit 1
fi

JHOME="$1"
shift
VERSION="$1"
shift
FILE_TO_DIFF=""
DIFF_CMD="diff_silent"
CHECK_FILE_BEFORE='log_clearable Checking'
CHECK_FILE_AFTER='log_clear'
if (( $# > 0 ))
then
	FILE_TO_DIFF="$1"
	DIFF_CMD="diff_patch"
	CHECK_FILE_BEFORE='true'
	CHECK_FILE_AFTER='true'
	shift
fi

TAG="${VERSION%.Final}"
WORK_DIR="/tmp/hibernate-orm-binary-check/$VERSION"
GIT_CLONE_DIR="$WORK_DIR/git-clone"
REBUILT_MAVEN_REPO_DIR="$WORK_DIR/rebuilt-maven-repo"
PUBLISHED_MAVEN_REPO_DIR="$WORK_DIR/published-maven-repo"
MAVEN_REPO="https://repo1.maven.org/maven2"
GRADLE_PLUGIN_REPO="https://plugins.gradle.org/m2"

rebuild() {
	if ! [ -e "$GIT_CLONE_DIR" ]
	then
		git clone --depth 1 git@github.com:hibernate/hibernate-orm.git -b "$TAG" "$GIT_CLONE_DIR"
	fi
	rm -rf "$REBUILT_MAVEN_REPO_DIR"
	mkdir -p "$REBUILT_MAVEN_REPO_DIR"
	pushd "$GIT_CLONE_DIR"
	./gradlew publishToMavenLocal -x test --no-build-cache -Dmaven.repo.local="$REBUILT_MAVEN_REPO_DIR" -Dorg.gradle.java.home="$JHOME"
	popd
}

ARTIFACT_COUNT=0
FILE_COUNT=0
FILE_DIFFERENT_COUNT=0

check() {
	mkdir -p "$PUBLISHED_MAVEN_REPO_DIR"
	if [ -n "$FILE_TO_DIFF" ]
	then
		check_artifact "$FILE_TO_DIFF"
	else
		trap "on_exit" EXIT
		for file in $(find "$REBUILT_MAVEN_REPO_DIR" -regex ".*/$VERSION/[^/]*" -type f -printf '%P\n')
		do
			check_artifact "$file"
		done
	fi
}

on_exit() {
	log "================================================================================"
	log "Examined $ARTIFACT_COUNT artifacts."
	log "Examined $FILE_COUNT files (identical files within JARs are not counted)."
	log "Found $FILE_DIFFERENT_COUNT files containing differences."
	log "Run $0 $JHOME $VERSION <file> to show the diff for a particular file."
	log "================================================================================"
}

check_artifact() {
	ARTIFACT_COUNT=$(( ARTIFACT_COUNT + 1 ))
	local name
	name="$1"
	local published_path
	published_path="$PUBLISHED_MAVEN_REPO_DIR/$name"
	local rebuilt_path
	rebuilt_path="$REBUILT_MAVEN_REPO_DIR/$name"
	download_published "$name" "$published_path"

	if ! [[ "$name" =~ .*\.jar ]]
	then
		check_file "$name" "$REBUILT_MAVEN_REPO_DIR/$name" "$PUBLISHED_MAVEN_REPO_DIR/$name"
		return
	fi

	# For JARs, inspect content
	local name_without_jar
	name_without_jar="${name%.jar}"

	local published_extracted_path
	published_extracted_path="$PUBLISHED_MAVEN_REPO_DIR/extracted/$name_without_jar"
	local rebuilt_extracted_path
	rebuilt_extracted_path="$REBUILT_MAVEN_REPO_DIR/extracted/$name_without_jar"
	extract_jar "$rebuilt_path" "$rebuilt_extracted_path"
	extract_jar "$published_path" "$published_extracted_path"

	# List new or different files
	for path in $(list_binary_different_files "$rebuilt_extracted_path" "$published_extracted_path")
	do
		check_file "$name: $path" "$rebuilt_extracted_path/$path" "$published_extracted_path/$path"
	done
}

download_published() {
	mkdir -p "$(dirname "$2")"
	local repo
	if [[ "$1" =~ gradle.plugin ]]
	then
		repo="$GRADLE_PLUGIN_REPO"
	else
		repo="$MAVEN_REPO"
	fi
	log_clearable "Downloading" "$repo/$1"
	if curl -f -s -S -o "$2" -L "$repo/$1"
	then
		log_clear
	else
		log "Download failed for $repo/$1"
		exit 1
	fi
}

check_file() {
	FILE_COUNT=$(( FILE_COUNT + 1 ))
	$CHECK_FILE_BEFORE "$1"
	if diff_file_ignoring_timestamps "$2" "$3"
	then
		$CHECK_FILE_AFTER
	else
		$CHECK_FILE_AFTER
		FILE_DIFFERENT_COUNT=$(( FILE_DIFFERENT_COUNT + 1 ))
		log "$1 differs!"
	fi
}

extract_jar() {
	log_clearable "Extracting" "$1"
	rm -rf "$2"
	mkdir -p "$2"
	if unzip -d "$2" "$1" 1>/dev/null
	then
		log_clear
	else
		log "Extraction failed for $1"
		exit 1
	fi
}

list_binary_different_files() {
	rsync -rcn --out-format="%n" "$1/" "$2/" \
  		&& rsync -rcn --out-format="%n" "$2/" "$1/" \
  		| sort -u \
  		| grep -v '/$'
}

diff_file_ignoring_timestamps() {
	if [[ "$1" =~ .*\.class ]]
	then
		$DIFF_CMD <(decompile "$1" | replace_timestamps) <(decompile "$2" | replace_timestamps)
	else
		$DIFF_CMD <(cat_silent "$1" | replace_common_text_differences) <(cat_silent "$2" | replace_common_text_differences)
	fi
}

cat_silent() {
	if ! [ -e "$1" ]
	then
		# Empty output for non-existing files
		return
	fi
	cat "$1"
}

replace_timestamps() {
	sed -E 's/20[[:digit:]]{2}-[[:digit:]]{1,2}-[[:digit:]]{1,2}([ T][[:digit:]]{2}:[[:digit:]]{2}(:[[:digit:]]{2})?)?/SOME_DATE/g'
}

replace_common_text_differences() {
	replace_timestamps | sed -E -f <(cat <<-EOF
	s/ ?aria-[^=]+="[^"]+"//g
	s/(document\.getElementById|document.querySelector)\([^)]+\)//g
	EOF
	)
}

decompile() {
	if ! [ -e "$1" ]
	then
		# Empty output for non-existing files
		return
	fi
	# TODO improve, this misreports constant pools as different
	javap -v "$1"
}

rebuild
check