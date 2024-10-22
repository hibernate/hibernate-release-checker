GIT_REMOTE=https://github.com/beikov/xjc-plugin-jakarta.git

java_version_for_version() {
	echo 17
}

fix_commits_for_version() {
	return 0
}

is_known_not_reproducible() {
	echo "$1" | grep -q -E -f <(cat <<-'EOF'
	# Just about any change can lead to difference in javadoc search indexes
	-javadoc.jar: (member|package|type)-search-index.zip
	# The JQuery version included in javadoc changes in *micro* versions of the JDK.
	# See for example https://bugs.openjdk.org/browse/JDK-8291029
	-javadoc.jar: legal/jqueryUI.md
	-javadoc.jar: jquery/jquery-ui.min.(js|css)
	EOF
	)
}

replace_common_text_differences() {
	replace_timestamps | sed -E -f <(cat <<-'EOF'
	# Generated XML files, in particular for gradle-plugin, may differ -- probably some missing post-processing
	/<\?xml version="1\.0" encoding="UTF-8"\?>/d
	s,<project xsi:schemaLocation="([^"]+)" xmlns:xsi="([^"]+)" xmlns="([^"]+)">,<project xmlns="\3" xmlns:xsi="\2" xsi:schemaLocation="\1">,g
	s,http://maven.apache.org/POM/4.0.0,https://maven.apache.org/POM/4.0.0,g
	s,http://maven.apache.org/xsd/maven-4.0.0.xsd,https://maven.apache.org/xsd/maven-4.0.0.xsd,g
	s/^(\s)+//g
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