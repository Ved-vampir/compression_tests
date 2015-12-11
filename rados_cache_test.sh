#/bin/bash -x

ceph_cmd="./ceph"
rados_cmd="./rados"
test_count=1
names=""
failed=0
succeeded=0

delete_pool() {
	pool_name="$1"
	$ceph_cmd osd pool delete $pool_name $pool_name --yes-i-really-really-mean-it
}


# Prework
rule=$($ceph_cmd osd crush rule list | grep "erasure-code")
if [ -z "$rule" ]; then
	echo "Create erasure crush rule before start"
	$ceph_cmd osd crush rule create-erasure erasure-code
fi

echo "Create Erasure Coded pool with compression, "
$ceph_cmd osd pool create obpool 128 128 erasure default erasure-code 0 zlib
echo "Create Cache tier for the created EC pool "
$ceph_cmd osd pool create cachepool 128 128
$ceph_cmd osd tier add obpool cachepool
$ceph_cmd osd tier cache-mode cachepool writeback
$ceph_cmd osd tier set-overlay obpool cachepool
echo "Set cache pool to flush ASAP"
$ceph_cmd osd pool set cachepool target_max_objects 1
$ceph_cmd osd pool set cachepool target_max_objects 1

check_osds_up() {
	responce=$($ceph_cmd osd tree | grep "down")
	if [ -n "$responce" ]; then
		err="FAILED: Not all osds are up"
		let "failed = failed + 1"
		names="$name:$err; $names"
		return -1
	fi
	return 0
}

# Tests
name="1. Rados load-gen verification"
echo "$name"
$rados_cmd -p cachepool load-gen
if [ $? -ne 0 ]; then
	err="FAILED: Failed load-gen"
	let "failed = failed + 1"
	names="$name:$err; $names"
	check_osds_up
	if [ $? -eq 0 ]; then
		let "succeeded = succeeded + 1"
fi

delete_pool obpool
delete_pool cachepool

echo "Report:"
echo "TOTAL:   $test_count"
echo "SUCCESS: $succeeded"
echo "FAILED:  $failed"
echo "Failed tests: $names"
