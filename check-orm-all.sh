#!/bin/bash

log() {
	echo 1>&2 "${@}"
}

mkdir -p /tmp/check-orm-all
OUT_DIR="$(mktemp -p /tmp/check-orm-all -d XXXXXX)"

log "Writing output to files in $OUT_DIR"

while read -r jdk version
do
	log "Checking $version..."
	{
		java_home_var_name="JAVA${jdk}_HOME"
		java_home="${!java_home_var_name}"
		if [ -z "$java_home" ]
		then
			echo "ERROR: \$$java_home_var_name is not set; unable to rebuild $version with JDK $jdk." | tee /dev/stderr
		else
			# Use </dev/null to avoid gradlew consuming all stdin.
			./check-orm.sh "${java_home}" "$version" </dev/null
		fi
	} 2>&1 | tee "$OUT_DIR/$version.log"
done <<EOF
11 6.2.25.Final
11 6.2.26.Final
11 6.2.27.Final
11 6.2.28.Final
11 6.2.29.Final
11 6.2.30.Final
11 6.2.31.Final
11 6.2.32.Final
11 6.4.5.Final
11 6.4.6.Final
11 6.4.7.Final
11 6.4.8.Final
11 6.4.9.Final
11 6.4.10.Final
11 6.5.0.CR2
11 6.5.0.Final
11 6.5.1.Final
11 6.5.2.Final
11 6.5.3.Final
11 6.6.0.Alpha1
11 6.6.0.CR1
11 6.6.0.CR2
17 6.6.0.Final
17 6.6.1.Final
17 7.0.0.Alpha2
17 7.0.0.Alpha3
17 7.0.0.Beta1
EOF

log "Wrote output to files in $OUT_DIR"