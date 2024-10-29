#!/bin/bash -Eeu

log() {
	echo 1>&2 "${@}"
}

abort() {
	log "Aborting."
	exit 1
}

usage() {
	log "
$0: rebuilds Hibernate projects for a specific version and checks that
  resulting Maven artifacts and documentation are equivalent to the ones
  published to Maven central and https://docs.jboss.org/hibernate.

Requirements:

  * A GNU/Linux environment -- not tested on other POSIX environments.
  * Various pre-installed commands, most of them usually installed by default:
    'git', 'diff', 'tput', 'unzip', 'curl', 'rsync', 'sed', ...
  * 'JAVA<number>_HOME' environment variables that point to the path of JDK installations,
    e.g. 'JAVA11_HOME', 'JAVA17_HOME', ...
  * Lots of disk space if you're going to check many versions:
    each build of Hibernate ORM has a multi-gigabyte disk footprint.

Usage:

  Check a given release of a Hibernate project:
    $0 [options] <project> <version>
  Check a single artifact or documentation file for a given release of a Hibernate project:
    $0 [options] <project> <version> <artifact-path>
  Check all releases listed in a file:
    $0 [options] <project> <file-name-without-extension>

Arguments:

  <project>:
    The name of a Hibernate project, case sensitive. Currently accepts 'orm' or 'hcann'.
  <version>:
    The version of the Hibernate project to rebuild and compare. Must include the '.Final' qualifier if relevant, e.g. '6.2.0.CR1' or '6.2.1.Final'.
  <artifact-path>:
    The path of a single artifact to diff, relative to the root of the Maven repository. You can simply copy-paste paths reported by the all-artifact diff.
  <file-name-without-extension>:
    The name of a file at path '<project>/<file-name-without-extension>.txt'.

Options:

  -h:
    Show this help and exit.
  -m:
    Check Maven artifacts (the default).
  -M:
    Do not check Maven artifacts.
  -d:
    Check documentation on docs.jboss.org.
  -D:
    Do not check documentation on docs.jboss.org (the default).
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

check_all_versions_from_file() {
	mkdir -p "$WORK_DIR_BASE"
	WORK_DIR="$(mktemp -p "$WORK_DIR_BASE" -d XXXXXX)"

	local versions
	mapfile -t versions < "$1"

	log "Will check the following versions one by one:"
	IFS=$'\n' log "${versions[@]}"
	log
	log "Output will be copied to files in $WORK_DIR"
	log
	read -p 'OK with that? [y/N] '
  [ "$REPLY" = 'y' ] || abort

	for version in "${versions[@]}"
	do
		{
			# Use </dev/null to avoid gradlew consuming all stdin.
			$0 "${ARGS_TO_FORWARD[@]}" "$version" </dev/null || log "Check failed."
		} 2>&1 | tee "$WORK_DIR/$version.log"
		log "Copied output to $WORK_DIR/$version.log"
	done

	log "Copied output to files in $WORK_DIR"
	log "Run the following command to display all reports:"
	log "$(cat <<-EOF
	find $WORK_DIR -name '*.log' | xargs -I {} bash -c 'grep "========" {} -A 50 | grep "======" -B 50' -- grep
	EOF
	)"
}

check_single_version_from_argument() {
	VERSION=$1
	shift

	log "Will check version $VERSION."
	log

	JHOME="$(java_home_for_version $VERSION)"

	if (( $# == 0 ))
	then
		FILE_TO_DIFF=""
		DIFF_CMD="diff_silent"
		CHECK_FILE_BEFORE='log_clearable Checking'
		CHECK_FILE_AFTER='log_clear'
		CHECK_FILE_LOG_NOT_REPRODUCIBLE='true'
	elif (( $# == 1 ))
	then
		FILE_TO_DIFF="$1"
		DIFF_CMD="diff_patch"
		CHECK_FILE_BEFORE='true'
		CHECK_FILE_AFTER='true'
		CHECK_FILE_LOG_NOT_REPRODUCIBLE='log'
		shift
	else
		log "ERROR: Wrong number of arguments."
		usage
		abort
	fi

  GIT_REF="$(git_ref_for_version)"
	WORK_DIR="$WORK_DIR_BASE/$VERSION"
	GIT_CLONE_DIR="$WORK_DIR/git-clone"
	REBUILT_MAVEN_REPO_DIR="$WORK_DIR/rebuilt-maven-repo"
	PUBLISHED_MAVEN_REPO_DIR="$WORK_DIR/published-maven-repo"
	PUBLISHED_DOCS_DIR="$WORK_DIR/published-docs"
	MAVEN_REPO="https://repo1.maven.org/maven2"
	GRADLE_PLUGIN_REPO="https://plugins.gradle.org/m2"
	DOCS_URL="https://docs.jboss.org/hibernate/$PROJECT/$(echo "$VERSION" | sed -E 's/^([0-9]+\.[0-9]+).*/\1/')"

	rebuild

	CHECK_DONE=0
	ARTIFACT_COUNT=0
	FILE_COUNT=0
	FILE_DIFFERENT_COUNT=0
	FILE_DIFFERENT_KNOWN_NOT_REPRODUCIBLE_COUNT=0

	if [ -z "$FILE_TO_DIFF" ]
	then
		trap "on_exit" EXIT
	fi

	if (( CHECK_MAVEN ))
	then
		mkdir -p "$PUBLISHED_MAVEN_REPO_DIR"
		if [ -n "$FILE_TO_DIFF" ]
		then
			check_artifact "$FILE_TO_DIFF"
		else
			for file in $(find "$REBUILT_MAVEN_REPO_DIR" -regex ".*/$VERSION/[^/]*" -type f -printf '%P\n')
			do
				check_artifact "$file"
			done
		fi
	fi
	if (( CHECK_DOCS ))
	then
		REBUILT_DOCS_DIR="$GIT_CLONE_DIR/$(docs_relative_path)"
		mkdir -p "$PUBLISHED_DOCS_DIR"
		if [ -n "$FILE_TO_DIFF" ]
		then
			check_docs_file "$FILE_TO_DIFF"
		else
			for file in $(find "$REBUILT_DOCS_DIR" -not -regex ".*/fragments/.*" -type f -printf '%P\n')
			do
				check_docs_file "$file"
			done
		fi
	fi
	CHECK_DONE=1
}

java_home_for_version() {
	local java_version="$(java_version_for_version)"
	local java_home_var_name
	java_home_var_name="JAVA${java_version}_HOME"
	if [ -z ${!java_home_var_name+x} ]
	then
		log "ERROR: Environment variable $java_home_var_name is not set; unable to find Java home for JDK $java_version, necessary to build Hibernate $PROJECT version $1."
		abort
	fi
	local java_home
	echo "${!java_home_var_name}"
}

rebuild() {
	if ! [ -e "$GIT_CLONE_DIR" ]
	then
		log "Cloning..."
		git clone --depth 1 $GIT_REMOTE -b "$GIT_REF" "$GIT_CLONE_DIR" 1>/dev/null
	fi
	cd "$GIT_CLONE_DIR"

	apply_build_fixes

	rm -rf "$REBUILT_MAVEN_REPO_DIR"
	mkdir -p "$REBUILT_MAVEN_REPO_DIR"

	log "Building using Java Home: $JHOME"
	./gradlew -x test --no-build-cache -Dmaven.repo.local="$REBUILT_MAVEN_REPO_DIR" -Dorg.gradle.java.home="$JHOME" \
		$( (( CHECK_MAVEN )) && echo publishToMavenLocal ) \
		$( (( CHECK_DOCS )) && gradle_options_for_docs )
}

apply_build_fixes() {
	local fix_commits
	fix_commits=($(fix_commits_for_version))
	local commits_to_apply=()
	for commit in ${fix_commits[@]}
	do
		if ! { git log HEAD~${#fix_commits[@]}..HEAD 2>/dev/null | grep -q "$commit"; }
		then
			# Apply the commit: it hasn't been applied yet
			commits_to_apply+=( "$commit" )
		fi
	done
	if (( ${#commits_to_apply[@]} != 0 ))
	then
		log "Fetching additional commits to fix the build..."
		git fetch origin "${commits_to_apply[@]}"
		log "Applying additional commits to fix the build..."
		git cherry-pick -x --empty=drop "${commits_to_apply[@]}"
	fi

	fix_for_version
}

on_exit() {
	echo "


================================================================================
Finished checking version $VERSION on $(date -Iminutes --utc) UTC

Used the following JDK:

$($JHOME/bin/java -version 2>&1 | sed "s/^/    /g")

Examined $ARTIFACT_COUNT artifacts.
Examined $FILE_COUNT files (identical files within JARs are not counted).

Ignored $FILE_DIFFERENT_KNOWN_NOT_REPRODUCIBLE_COUNT files containing differences,
but that are known not to be reproducible: require a specific OpenJDK micro version,
unpredictable order of content that doesn't change semantics, ...

$(tput bold)Found $FILE_DIFFERENT_COUNT files containing significant differences.$(tput sgr0)
$((( CHECK_DONE != 1 )) && echo -e "\nWARNING: This check was terminated unexpectedly, this report is incomplete.")
================================================================================"
	if (( CHECK_MAVEN))
	then
		echo "Run $0 $PROJECT $VERSION <artifact-path> to show the diff for a particular artifact."
	fi
	if (( CHECK_DOCS))
	then
		echo "Run $0 -dM $PROJECT $VERSION <file-path> to show the diff for a documentation file."
	fi
}

check_artifact() {
	ARTIFACT_COUNT=$(( ARTIFACT_COUNT + 1 ))
	local name
	name="$1"
	local published_path
	published_path="$PUBLISHED_MAVEN_REPO_DIR/$name"
	local rebuilt_path
	rebuilt_path="$REBUILT_MAVEN_REPO_DIR/$name"
	download_artifact "$name" "$published_path"

	if ! [[ "$name" =~ .*\.jar$ ]]
	then
		check_file "$name" "$REBUILT_MAVEN_REPO_DIR/$name" "$PUBLISHED_MAVEN_REPO_DIR/$name"
		return
	fi

	# For JARs, inspect content
	FILE_COUNT=$(( FILE_COUNT + 1 ))
	local name_without_jar
	name_without_jar="${name%.jar}"

	local published_extracted_path
	published_extracted_path="$PUBLISHED_MAVEN_REPO_DIR/extracted/$name_without_jar"
	local rebuilt_extracted_path
	rebuilt_extracted_path="$REBUILT_MAVEN_REPO_DIR/extracted/$name_without_jar"
	extract "$rebuilt_path" "$rebuilt_extracted_path"
	extract "$published_path" "$published_extracted_path"

	# List new or different files
	for path in $(list_binary_different_files "$rebuilt_extracted_path" "$published_extracted_path")
	do
		check_file "$name: $path" "$rebuilt_extracted_path/$path" "$published_extracted_path/$path"
	done

	rm -rf "$rebuilt_extracted_path" "$published_extracted_path"
}

download_artifact() {
	if [ -f "$2" ]
	then
		# Already downloaded
		return 0
	fi
	mkdir -p "$(dirname "$2")"
	local repo
	if [[ "$1" =~ gradle.plugin ]] || [[ "$1" =~ "/gradle/" ]]
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

check_docs_file() {
	local name
	name="$1"
	local published_path
	published_path="$PUBLISHED_DOCS_DIR/$name"
	local rebuilt_path
	rebuilt_path="$REBUILT_DOCS_DIR/$name"
	download_docs "$name" "$published_path"

	if ! [[ "$name" =~ .*\.zip$ ]]
	then
		check_file "$name" "$REBUILT_MAVEN_REPO_DIR/$name" "$PUBLISHED_MAVEN_REPO_DIR/$name"
		return
	fi

	# For ZIPs, inspect content
	FILE_COUNT=$(( FILE_COUNT + 1 ))
	local name_without_zip
	name_without_zip="${name%.zip}"

	local published_extracted_path
	published_extracted_path="$PUBLISHED_DOCS_DIR/extracted/$name_without_zip"
	local rebuilt_extracted_path
	rebuilt_extracted_path="$REBUILT_DOCS_DIR/extracted/$name_without_zip"
	extract "$rebuilt_path" "$rebuilt_extracted_path"
	extract "$published_path" "$published_extracted_path"

	# List new or different files
	for path in $(list_binary_different_files "$rebuilt_extracted_path" "$published_extracted_path")
	do
		check_file "$name: $path" "$rebuilt_extracted_path/$path" "$published_extracted_path/$path"
	done

	rm -rf "$rebuilt_extracted_path" "$published_extracted_path"
}

download_docs() {
	if [ -f "$2" ]
	then
		# Already downloaded
		return 0
	fi
	mkdir -p "$(dirname "$2")"
	log_clearable "Downloading" "$DOCS_URL/$1"
	if curl -f -s -S -o "$2" -L "$DOCS_URL/$1"
	then
		log_clear
	else
		log
		log "Download failed for $DOCS_URL/$1"
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

extract() {
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
	if [[ "$1" =~ .*\.class$ ]]
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
	sed -E 's/20[[:digit:]]{2}-[[:digit:]]{1,2}-[[:digit:]]{1,2}([ T][[:digit:]]{2}:[[:digit:]]{2}(:[[:digit:]]{2})?( \+[[:digit:]]{2,4}| UTC)?)?/SOME_DATE/g'
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
	javap -v "$1" | grep -Ev '^Classfile .*\.class$|^  SHA-256 checksum|^  MD5 checksum|^  Last modified'
}

CHECK_MAVEN=1
CHECK_DOCS=0

while getopts 'hdDmM' opt
do
	case "$opt" in
		h)
			usage
			exit 0
			;;
		m)
			CHECK_MAVEN=1
			;;
		M)
			CHECK_MAVEN=0
			;;
		d)
			CHECK_DOCS=1
			;;
		D)
			CHECK_DOCS=0
			;;
		\?)
			usage
			abort
			;;
	esac
done

ARGS_TO_FORWARD=( "$@" )
unset 'ARGS_TO_FORWARD[-1]'
shift $(( OPTIND - 1 ))

if (( $# < 1 ))
then
	log "ERROR: Wrong number of arguments."
	usage
	abort
fi

if (( CHECK_MAVEN )) && (( CHECK_DOCS ))
then
	if (( $# > 2 ))
	then
		log "ERROR: Cannot pass a specific artifact when checking both Maven artifacts and docs."
		usage
		abort
	fi
fi

if (( CHECK_MAVEN ))
then
	log "Will check Maven artifacts"
else
	log "Will NOT check Maven artifacts"
fi

if (( CHECK_DOCS ))
then
	log "Will check documentation"
else
	log "Will NOT check documentation"
fi

if ! (( CHECK_MAVEN )) && ! (( CHECK_DOCS))
then
	log "Nothing to check!"
	abort
fi

SCRIPT_DIR="$(readlink -f ${BASH_SOURCE[0]} | xargs dirname)"

PROJECT="$1"
shift
SPECIFICS_PATH="$SCRIPT_DIR/$PROJECT/specifics.sh"
if ! [ -f "$SPECIFICS_PATH" ]
then
	log "ERROR: unsupported Hibernate project: $PROJECT."
	abort
fi
source "$SPECIFICS_PATH"

WORK_DIR_BASE="/tmp/hibernate-release-checker/$PROJECT"

LIST_PATH="$SCRIPT_DIR/$PROJECT/$1.txt"
if [ -f "$LIST_PATH" ]
then
	log "Interpreting '$1' as a set of versions to test, listed in $LIST_PATH."
	log
	if (( $# > 1 ))
	then
		log "ERROR: Cannot pass a specific artifact when checking a set of versions."
		usage
		abort
	fi
	check_all_versions_from_file "$LIST_PATH"
elif [[ "$1" =~ ^[1-9][0-9]*\.[0-9]+\.[0-9]+\..*$ ]]
then
	log "Interpreting '$1' as a single version to test."
	log
	check_single_version_from_argument "${@}"
elif [[ $PROJECT = "xjc" ]] || [[ "$1" =~ ^[1-9][0-9]*\.[0-9]+\.[0-9]+$ ]]
then
	log "Interpreting '$1' as a single version to test."
	log
	check_single_version_from_argument "${@}"
else
	log "ERROR: $1 is not a file, nor a correctly formed, complete Hibernate $PROJECT version."
	abort
fi
