#!/bin/bash -Eeu

log() {
	echo 1>&2 "${@}"
}

usage() {
	log "
$0: Rebuilds Hibernate ORM for a specific tag and diffs the resulting binaries with published Maven artifacts.

Usage:
  To diff all artifacts published for a given version of Hibernate ORM:
      $0 <java-home> <version>
  To diff a single artifact published for a given version of Hibernate ORM:
      $0 <java-home> <version> <artifact-path>

  <java-home>:
    The path to a JDK. Must be the same major version, preferably even the same build, as the one used to build the published artifacts.
  <version>:
    The version of Hibernate ORM to rebuild and compare. Must include the '.Final' qualifier if relevant, e.g. '6.2.0.CR1' or '6.2.1.Final'.
  <artifact-path>:
    The path of a single artifact to diff, relative to the root of the Maven repository. You can simply copy-paste paths reported by the all-artifact diff.
"
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
	tput >/dev/tty sc
	echo >/dev/tty -n "$prefix$suffix"
}

log_clear() {
	tput >/dev/tty el el1 rc
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
CHECK_FILE_LOG_NOT_REPRODUCIBLE='true'
if (( $# > 0 ))
then
	FILE_TO_DIFF="$1"
	DIFF_CMD="diff_patch"
	CHECK_FILE_BEFORE='true'
	CHECK_FILE_AFTER='true'
	CHECK_FILE_LOG_NOT_REPRODUCIBLE='log'
	shift
fi

TAG="${VERSION%.Final}"
WORK_DIR="/tmp/hibernate-binary-check/orm/$VERSION"
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
	cd "$GIT_CLONE_DIR"
	./gradlew publishToMavenLocal -x test --no-build-cache -Dmaven.repo.local="$REBUILT_MAVEN_REPO_DIR" -Dorg.gradle.java.home="$JHOME"
}

CHECK_DONE=0
ARTIFACT_COUNT=0
FILE_COUNT=0
FILE_DIFFERENT_COUNT=0
FILE_DIFFERENT_KNOWN_NOT_REPRODUCIBLE_COUNT=0

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
	CHECK_DONE=1
}

on_exit() {
	echo "


================================================================================
Finished checking version $VERSION on $(date -Iminutes --utc) UTC

Used the following JDK:

$($JHOME/bin/java -version 2>&1 | sed "s/^/    /g")

Examined $ARTIFACT_COUNT artifacts.
Examined $FILE_COUNT files (identical files within JARs are not counted).
Ignored $FILE_DIFFERENT_KNOWN_NOT_REPRODUCIBLE_COUNT files containing differences, but that are known not to be reproducible.

$(tput bold)Found $FILE_DIFFERENT_COUNT files containing significant differences.$(tput sgr0)
$((( CHECK_DONE != 1 )) && echo -e "\nWARNING: This check was terminated unexpectedly, this report is incomplete.")
================================================================================
Run $0 $JHOME $VERSION <artifact-path> to show the diff for a particular artifact.
================================================================================"
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

	rm -rf "$rebuilt_extracted_path" "$published_extracted_path"
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
		log
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
	elif is_known_not_reproducible "$1"
	then
		$CHECK_FILE_AFTER
		FILE_DIFFERENT_KNOWN_NOT_REPRODUCIBLE_COUNT=$(( FILE_DIFFERENT_KNOWN_NOT_REPRODUCIBLE_COUNT + 1 ))
		$CHECK_FILE_LOG_NOT_REPRODUCIBLE "NOTE: $1 differs, but is known not to be reproducible, and is therefore ignored."
	else
		$CHECK_FILE_AFTER
		FILE_DIFFERENT_COUNT=$(( FILE_DIFFERENT_COUNT + 1 ))
		echo "$1 differs!"
	fi
}

is_known_not_reproducible() {
	echo "$1" | grep -E -f <(cat <<-'EOF'
	hibernate-core-[^-]+.jar: org/hibernate/boot/jaxb/hbm/spi/JaxbHbm((Id)?BagCollection|List|Map|Set)Type\.class
	hibernate-core-[^-]+-sources.jar: (hbm/)?org/hibernate/boot/jaxb/hbm/spi/JaxbHbm((Id)?BagCollection|List|Map|Set)Type\.java
	hibernate-core-[^-]+-javadoc.jar: org/hibernate/boot/jaxb/hbm/spi/JaxbHbm((Id)?BagCollection|List|Map|Set)Type\.html
	-javadoc.jar: (member|package|type)-search-index.zip
	org/hibernate/orm/hibernate-gradle-plugin/[^/]+/hibernate-gradle-plugin-[^\-]+\.(pom|module)
	EOF
	)
}

extract_jar() {
	log_clearable "Extracting" "$1"
	rm -rf "$2"
	mkdir -p "$2"
	if unzip -d "$2" "$1" 1>/dev/null
	then
		log_clear
	else
		log
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
	replace_timestamps | sed -E -f <(cat <<-'EOF'
	/<\?xml version="1\.0" encoding="UTF-8"\?>/d
	s,<project xsi:schemaLocation="([^"]+)" xmlns:xsi="([^"]+)" xmlns="([^"]+)">,<project xmlns="\3" xmlns:xsi="\2" xsi:schemaLocation="\1">,g
	s,http://maven.apache.org/POM/4.0.0,https://maven.apache.org/POM/4.0.0,g
	s,http://maven.apache.org/xsd/maven-4.0.0.xsd,https://maven.apache.org/xsd/maven-4.0.0.xsd,g
	s/^(\s)+//g
	s/ ?aria-[^=]+="[^"]+"//g
	s/(document\.getElementById|document\.querySelector)\([^)]+\)//g
	$a\\
	EOF
	)
}

decompile() {
	if ! [ -e "$1" ]
	then
		# Empty output for non-existing files
		return
	fi
	# Note this misreports constant pools as different if their ordering differs,
	# thus one must use the same JDK that was used for published artifacts.
	# For instance, JDK 21 is known to produce constant pools that are different
	# from those generated by JDK 11.
	javap -v "$1"
}

rebuild
check
