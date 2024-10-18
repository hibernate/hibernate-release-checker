GIT_REMOTE=git@github.com:hibernate/hibernate-orm.git

java_version_for_version() {
	if [[ "$VERSION" =~ ^[12345]\..*$ ]]
	then
		log "ERROR: unsupported Hibernate ORM version: $VERSION."
		abort
	elif [[ "$VERSION" =~ ^6\..*$ ]] && ! [[ "$1" =~ ^6.6.0.Final$ ]]
	then
		echo 11
	else
		echo 17
	fi
}

fix_commits_for_version() {
	# A few commits to fix builds that no longer work due to e.g. changes in Maven repositories.
	# See:
	# https://github.com/hibernate/hibernate-orm/commit/1da18451ce9adf40c5939d050b6914cb7529e6eb
	# https://github.com/hibernate/hibernate-orm/commit/e4a0b6988f84e85e427484e65321e9583080ccb5
	# https://github.com/hibernate/hibernate-orm/commit/420faa7e4ac8a5065ed42f8338883193c944ff76
	if [[ "$VERSION" =~ ^7\.0\.0\.Alpha ]] || [[ "$VERSION" =~ ^6\.6\.0\.(Alpha|Beta|CR1) ]]
	then
		echo "1da18451ce9adf40c5939d050b6914cb7529e6eb" "e4a0b6988f84e85e427484e65321e9583080ccb5" "420faa7e4ac8a5065ed42f8338883193c944ff76"
	elif [[ "$VERSION" =~ ^6\.5\.[0-2]\..* ]]
	then
		echo "26f20caa6370bbf7077927823324dc674dba9387" "b2edca91dcc0a925bbd10b7d327871f5b81e2eea" "ea6dfd764f4d65d65e144e625fac579a2905f1fb"
	elif [[ "$VERSION" =~ ^6\.4\.[0-9]\. ]] || [[ "$VERSION" =~ ^6\.3\. ]]
	then
		echo "f67acfcd65e4d78f2c0a91e883250c381478729c" "6f3258a97f4f7b7bd6e0e8f1fda4337ff74b6c98" "7ef269100b7bce5a2dab9f8c3097fd51d5cb56c4"
	elif [[ "$VERSION" =~ ^6\.2\.[012][0-9]?\. ]]
	then
		echo "97e6f458192855692f2953020988da8fd3f844f7" "f810f648f9816ded3ae9e17a3ccf7f7c175b1cb7" "7ef269100b7bce5a2dab9f8c3097fd51d5cb56c4"
	else
		# Nothing to do
		return 0
	fi
}

is_known_not_reproducible() {
	echo "$1" | grep -q -E -f <(cat <<-'EOF'
	# These JAXB classes are generated, but the order of fields/getters/setters is semi-random (generator uses a HashSet)
	hibernate-core-[^-]+.jar: org/hibernate/boot/jaxb/hbm/spi/JaxbHbm((Id)?BagCollection|List|Map|Set)Type\.class
	hibernate-core-[^-]+-sources.jar: (hbm/)?org/hibernate/boot/jaxb/hbm/spi/JaxbHbm((Id)?BagCollection|List|Map|Set)Type\.java
	hibernate-core-[^-]+-javadoc.jar: org/hibernate/boot/jaxb/hbm/spi/JaxbHbm((Id)?BagCollection|List|Map|Set)Type\.html
	# Just about any change can lead to difference in javadoc search indexes
	-javadoc.jar: (member|package|type)-search-index.zip
	# The gradle plugin metadata is wrong, because we're using a hack to get it published using publishToMavenLocal
	# (it's normally published using a different task that is specific to Gradle plugins)
	org/hibernate/orm/hibernate-gradle-plugin/[^/]+/hibernate-gradle-plugin-[^\-]+\.(pom|module)
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