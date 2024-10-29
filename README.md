# hibernate-release-checker

## Description

Script that rebuilds Hibernate projects for a specific version and checks that resulting Maven artifacts and documentation are equivalent to the ones published to Maven central and https://docs.jboss.org/hibernate.

Since older versions of Hibernate projects (ORM before https://github.com/hibernate/hibernate-orm/pull/8790, and perhaps other PRs) do not have a reproducible build, the script is more forgiving than a simple bit-by-bit comparison:

* JARs are extracted and their entries compared, because the JARs format records timestamps that differ from one build to the next.
* Text files get timestamps and other known differences (e.g. `aria-` tags in HTML) replaced.
* Some generated source files (e.g. JAXB data classes) are consistently ignored, because the order of methods in these files is unpredictable. 

See the source of the script for more details.

## Check history

Versions that have been checked by team members are listed in `CHECKED.md`.

## Requirements

* A GNU/Linux environment -- not tested on other POSIX environments.
* Various pre-installed commands, most of them usually installed by default:
  `git`, `diff`, `tput`, `unzip`, `curl`, `rsync`, `sed`, ...
* `JAVA<number>_HOME` environment variables that point to the path of JDK installations, e.g. `JAVA11_HOME`, `JAVA17_HOME`, ...
* Lots of disk space if you're going to check many versions: each build of Hibernate ORM has a multi-gigabyte disk footprint.

## Usage

Run `./check.sh -h` for help.

## Examples

Check all published Maven artifacts for Hibernate ORM 6.6.0.Final:

```shell
./check.sh orm 6.6.0.Final
```

Check all published Maven artifacts for Hibernate Commons Annotations 7.0.1.Final:

```shell
./check.sh hcann 7.0.1.Final
```

Check `hibernate-core.jar` for Hibernate ORM 6.6.0.Final:

```shell
./check.sh orm 6.6.0.Final org/hibernate/orm/hibernate-core/6.6.0.Final/hibernate-core-6.6.0.Final.jar
```

Check `hibernate-gradle-plugin.pom` for Hibernate ORM 6.6.0.Final:

```shell
./check.sh orm 6.6.0.Final org/hibernate/orm/hibernate-gradle-plugin/6.6.0.Final/hibernate-gradle-plugin-6.6.0.Final.pom
```

Check all published Maven artifacts for all versions of Hibernate ORM published between April 2024 and October 2024:

```shell
./check.sh orm 2024-04-to-10
```

Check all documentation published to docs.jboss.org for all releases of Hibernate ORM between April 2024 and October 2024:

```shell
./check.sh -dM orm 2024-04-to-10-latest
```

## Disclaimers

* Terminal output is best-effort: it is known to glitch from time to time.
* This tool currently handles a few targeted versions only.
  We only intend to support checking newer/older versions as the need arises.
* Some versions of Hibernate projects may not build properly.
  If so, you need to contribute hacks to the `fix_commits_for_version()` or `fix_for_version()` functions in `project>/specifics.sh`.
* Some versions of Hibernate projects may have additional known differences in text files from one build to the next.
  If so, you need to contribute additional `sed` replacements to the `replace_common_text_differences()` function in `<project>/specifics.sh`.
* Some versions of Hibernate projects may have additional non-reproducible files.
  If so, you need to contribute additional patterns to the `is_known_not_reproducible()` function in `<project>/specifics.sh`.