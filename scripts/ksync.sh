#!/bin/sh
set -e

my_name="${0##*/}"

# If an argument is given, it's the location
# of the Linux kernel source tree
k_dir="${1}"
if [ ! \( -n "${k_dir}" -a -d "${k_dir}/kernel" \) ]; then
    if [ -n "${k_dir}" ]; then
        printf "%s: \`%s': not a Linux kernel source tree\n"    \
               "${my_name}" "${k_dir}"
    else
        printf "Usage: %s /path/to/kernel/dir\n" "${my_name}"
    fi
    exit 1
fi

# Save current version
k_cset_old=$( head -n 1 .version |awk '{ print $(2); }' )

# Get the kernel version
eval $( grep -v 'SPDX-License-Identifier' "${k_dir}/Makefile" \
        |head -n 5                                            \
        |sed -e 's/^/K_/; s/"//g; s/ = \{0,1\}/="/; s/$/"/;'  \
      )
k_cset="$( cd "${k_dir}";                   \
           git log -n 1 --pretty='format:%H' \
         )"
printf "Found Linux kernel %d.%d.%d%s '%s' (%7.7s)\n"   \
       "${K_VERSION}" "${K_PATCHLEVEL}" "${K_SUBLEVEL}" \
       "${K_EXTRAVERSION}" "${K_NAME}" "${k_cset}"

# Get the kconfig-frontends version
kf_version="$( tail -n 1 .version )"

# Store the new version
printf "%d.%d.%d%s %s %s\n%s\n"             \
       "${K_VERSION}" "${K_PATCHLEVEL}"     \
       "${K_SUBLEVEL}" "${K_EXTRAVERSION}"  \
       "${k_cset}" "${K_NAME}"              \
       "${kf_version}"                      \
       >.version

# Sync-up the files
k_files=""
d_files=""
while read k_file trash kf_file; do
    k_files="${k_files} ${k_file}"
    mkdir -p "${kf_file%/*}"
    if [ -f "${k_dir}/${k_file}" ]; then
      cp -v "${k_dir}/${k_file}" "${kf_file}"
    else
      test -f "${kf_file}" && rm -v "${kf_file}"
      test -f "${kf_file}.patch" && rm -v "${kf_file}.patch"
      d_files="${d_files} ${k_file}"
    fi
    if [ -f "${kf_file}.patch" ]; then
        patch --no-backup-if-mismatch -g0 -F1 -p1 -f <"${kf_file}.patch" || :
    fi
done <scripts/ksync.list
for d_file in ${d_files}; do
    sed -e "\|${d_file}|d" -i scripts/ksync.list
done

# Save the changelog between the old cset and now
printf "Synced-up these changes:\n"
( cd "${k_dir}"
  test "${k_cset_old}" != "${k_cset}" &&        \
  git log -1 --pretty='tformat:%h %s'           \
    "${k_cset}"                                 \
    --
  git log --no-merges --pretty='tformat:%h %s'  \
    "${k_cset_old}..${k_cset}"                  \
    -- ${k_files}
)|tac                                           \
 |tee -a "scripts/ksync.log"                    \
 |sed -e 's/^/    /;'
