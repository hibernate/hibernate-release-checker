GIT_REMOTE=git@github.com:hibernate/hibernate-reactive.git

git_ref_for_version() {
  echo "${VERSION}"
}

java_version_for_version() {
  echo 11
}

fix_for_version() {
  return 0
}

fix_commits_for_version() {
  # Nothing to do
  return 0
}

