#!/bin/bash -e

log() {
	echo 2>&1 "${@}"
}

usage() {
	log "Usage:   $0 <version-including-.Final-if-relevant>"
}

if (( $# != 1 ))
then
	log "Missing argument"
	usage
	exit 1
fi

VERSION="$1"
TAG="${1%.Final}"
WORK_DIR="/tmp/hibernate-orm-binary-check/$VERSION"
GIT_CLONE_DIR="$WORK_DIR/git-clone"
REBUILT_MAVEN_REPO_DIR="$WORK_DIR/rebuilt-maven-repo"
PUBLISHED_MAVEN_REPO_DIR="$WORK_DIR/published-maven-repo"
MAVEN_REPO="https://repo1.maven.org/maven2"
GRADLE_PLUGIN_REPO="https://plugins.gradle.org/m2/"

FILES=0
FILES_WITH_TIMESTAMP_DIFF=0
FILES_WITH_CRITICAL_DIFF=0

rebuild() {
	if ! [ -e "$GIT_CLONE_DIR" ]
	then
		git clone --depth 1 git@github.com:hibernate/hibernate-orm.git -b "$TAG" "$GIT_CLONE_DIR"
	fi
	pushd "$GIT_CLONE_DIR"
	git clean -f
	./gradlew clean publishToMavenLocal -x test --no-build-cache -Dmaven.repo.local="$REBUILT_MAVEN_REPO_DIR"
	popd
}

check() {
	find "$REBUILT_MAVEN_REPO_DIR" -regex ".*/$VERSION/[^/]*" -type f -printf "%P\0" \
		| while read -d $'\0' name
		do
			log "Checking $name"
			check_artifact $name
		done
}

check_artifact() {
	local name
	name="$1"
	local published_path
	published_path="$PUBLISHED_MAVEN_REPO_DIR/$name"
	local rebuilt_path
	rebuilt_path="$REBUILT_MAVEN_REPO_DIR/$name"
	download_published "$name" "$published_path"

	if diff -q "$REBUILT_MAVEN_REPO_DIR/$name" "$PUBLISHED_MAVEN_REPO_DIR/$name" >/dev/null
	then
		return
	elif ! [[ "$name" =~ ".*\.jar" ]]
	then
		# TODO does not work?
		FILES_WITH_CRITICAL_DIFF=$(( $FILES_WITH_CRITICAL_DIFF + 1 ))
		log "$name differs!"
		return
	fi

	# A JAR differs -- inspect its content

	local published_extracted_path
	published_extracted_path="$PUBLISHED_MAVEN_REPO_DIR/extracted/$name"
	local rebuilt_extractedpath
	rebuilt_extractedpath="$REBUILT_MAVEN_REPO_DIR/extracted/$name"
	extract_jar "$rebuilt_path" "$rebuilt_extracted_path"
	extract_jar "$published_path" "$published_extracted_path"

	# List new or different files
	list_binary_different_files "$rebuilt_extracted_path" "$published_extracted_path" \
		| while read -d $'\n' path
     	do
     		if ! diff_file_ignoring_timestamps "$rebuilt_extracted_path/$path" "$published_extracted_path/$path"
     		then
					log "$name: $path differs!"
					FILES_WITH_CRITICAL_DIFF=$(( $FILES_WITH_CRITICAL_DIFF + 1 ))
				else
					FILES_WITH_CRITICAL_DIFF=$(( $FILES_WITH_TIMESTAMP_DIFF + 1 ))
     		fi
     	done
}

list_binary_different_files() {
	rsync -rcn --out-format="%n" "$1" "$2" \
  		&& rsync -rcn --out-format="%n" "$2" "$1" \
  		| sort -u
}

diff_file_ignoring_timestamps() {
	# TODO implement check, something like:
	# javap -v $1 | grep -v "<pattern for Generated annotation>"
	return 1
}

download_published() {
	mkdir -p "$(dirname "$2")"
	local repo
	if [[ "$1" =~ "gradle\.plugin" ]]
	then
		repo="$GRADLE_PLUGIN_REPO"
	else
		repo="$MAVEN_REPO"
	fi
	curl -s -o "$2" "$repo/$1"
}

extract_jar() {
	unzip -d "$2" "$1"
}

mkdir -p "$REBUILT_MAVEN_REPO_DIR"
mkdir -p "$PUBLISHED_MAVEN_REPO_DIR"

#rebuild
check

log "Ignored $FILES_WITH_TIMESTAMP_DIFF files differing only by an embedded timestamp."

if (( $FILES_WITH_CRITICAL_DIFF > 0 ))
then
	log "Found $FILES_WITH_CRITICAL_DIFF critical differences! See file names above."
	exit 128
else
	log "No critical difference found."
	exit 0
fi