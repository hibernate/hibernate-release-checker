# hibernate-binary-checker

## Description

Script that rebuilds Hibernate projects for a specific version and diffs the resulting binaries with published Maven artifacts.

Since older versions of Hibernate projects (ORM before https://github.com/hibernate/hibernate-orm/pull/8790, and perhaps other PRs) do not have a reproducible build, the script is more forgiving than a simple bit-by-bit comparison:

* JARs are extracted and their entries compared, because the JARs format records timestamps that differ from one build to the next.
* Text files get timestamps and other known differences (e.g. `aria-` tags in HTML) replaced.
* Some generated source files (e.g. JAXB data classes) are consistently ignored.

See the source of the script for more details.

## Check history

Artifacts that have been checked by team members are listed in `CHECKED.md`.

## Requirements

* A GNU/Linux environment -- not tested on other POSIX environments.
* Various pre-installed commands, most of them usually installed by default:
  `git`, `diff`, `tput`, `unzip`, `curl`, `rsync`, `sed`, ...

## Usage

IMPORTANT: This script expects `JAVA<number>_HOME` environment variables to be set to point to the path of JDK installations, e.g. `JAVA11_HOME`, `JAVA17_HOME`, ...

To diff all artifacts published for a given version of a Hibernate project:

```
./check.sh <project> <version>
```

To diff a single artifact published for a given version of a Hibernate project:

```
./check.sh <project> <version> <artifact-path>
```

To diff all artifacts published for all versions of Hibernate ORM published between April 2024 and October 2024:

```
./check.sh orm 2024-04-to-10
```

Arguments:

* `<project>`: The name of a Hibernate project, case sensitive. Currently accepts `orm` or `hcann`.
* `<version>`: The version of the Hibernate project to rebuild and compare. Must include the `.Final` qualifier if relevant, e.g. `6.2.0.CR1` or `6.2.1.Final`.
* `<artifact-path>`: The path of a single artifact to diff, relative to the root of the Maven repository. You can simply copy-paste paths reported by the all-artifact diff.

## Examples

```shell
./check.sh orm 6.6.0.Final
```

```shell
./check.sh hcann 7.0.1.Final
```

```shell
./check.sh orm 6.6.0.Final org/hibernate/orm/hibernate-core/6.6.0.Final/hibernate-core-6.6.0.Final.jar
```

```shell
./check.sh orm 6.6.0.Final org/hibernate/orm/hibernate-gradle-plugin/6.6.0.Final/hibernate-gradle-plugin-6.6.0.Final.pom
```

## Contributing

* Terminal output is best-effort; it might glitch from time to time.
* Some versions of Hibernate projects may not build properly.
  If so, you need to contribute hacks to the `rebuild()` function in `check.sh`.
* Some versions of Hibernate projects may have additional known differences in text files from one build to the next.
  If so, you need to contribute additional `sed` replacements to the `replace_common_text_differences()` function in `<project>/specifics.sh`.
* Some versions of Hibernate projects may have additional non-reproducible files.
  If so, you need to contribute additional patterns to the `is_known_not_reproducible()` function in `<project>/specifics.sh`.