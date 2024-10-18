GIT_REMOTE=git@github.com:hibernate/hibernate-commons-annotations.git

java_version_for_version() {
	if [[ "$VERSION" =~ ^[12345]\..*$ ]]
	then
		log "ERROR: unsupported Hibernate Commons Annotations version: $VERSION."
		abort
	elif [[ "$VERSION" == "7.0.0.Final" ]]
	then
		echo 17
	else
		echo 11
	fi
}

fix_commits_for_version() {
	# A few commits to fix builds that no longer work due to e.g. changes in Maven repositories.
	# See:
	# https://github.com/hibernate/hibernate-commons-annotations/commit/c9321ac8f71d8e0f2493058229c684496415d068
	echo "c9321ac8f71d8e0f2493058229c684496415d068"
}


is_known_not_reproducible() {
	echo "$1" | grep -q -E -f <(cat <<-'EOF'
	# Just about any change can lead to difference in javadoc search indexes
	-javadoc.jar: (member|package|type|module)-search-index.zip
	# The JQuery version included in javadoc changes in *micro* versions of the JDK.
	# See for example https://bugs.openjdk.org/browse/JDK-8291029
	-javadoc.jar: legal/jqueryUI.md
	-javadoc.jar: jquery/jquery-ui.min.(js|css)
	EOF
	)
}

replace_common_text_differences() {
	replace_timestamps | sed -E -f <(cat <<-'EOF'
	# Javadoc generation uses different aria- attributes depending on the JDK's micro version
	s/ ?aria-[^=]+="[^"]+"//g
	# Javadoc generation uses different javascript depending on the JDK's micro version
	s/(document\.getElementById|document\.querySelector)\([^)]+\)//g
	# Some files may not have a newline at their end -- we don't care
	$a\\
	# Links with anchors may not be generated correctly in the rebuild for some reason
	s,<a href="[^"#]*#[^"]+">,,g
	s,</a>,,g
	EOF
	)
}