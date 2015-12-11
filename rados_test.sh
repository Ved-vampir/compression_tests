#/bin/bash -x

ceph_cmd="./ceph"
rados_cmd="./rados"
cs_pool="obpool"
noncs_pool="ec_no_compression_pool"
cs_type="zlib"
test_obj_size="100M"
test_obj_parts="25M"
test_obj_parts_count=4
test_folder="tmp_test_folder"
test_count=32
names=""
failed=0
succeeded=0

delete_pool() {
	pool_name="$1"
	$ceph_cmd osd pool delete $pool_name $pool_name --yes-i-really-really-mean-it
}

delete_object() {
	pool_name="$1"
	obj_name="$2"
	$rados_cmd -p $pool_name rm $obj_name
}

# functions for use in cycle
put_object() {
	$rados_cmd -p "$1" put "$3" "$2"
	if [ $? -ne 0 ]; then
		err="FAILED: Cannot put object"
		let "failed = failed + 1"
		names="$name:$err; $names"
		continue
	fi
}

check_lspool() {
	responce=$($rados_cmd -p "$1" ls | grep "$2")
	if [ -z "$responce" ]; then
		err="FAILED: Object is not in pool"
		let "failed = failed + 1"
		names="$name:$err; $names"
		continue
	fi
}

get_object() {
	$rados_cmd -p "$1" get "$2" "$3"
	if [ $? -ne 0 ]; then
		err="FAILED: Cannot get object"
		let "failed = failed + 1"
		names="$name:$err; $names"
		continue
	fi
}

cmp_objects() {
	responce=$(cmp "$1" "$2")
	if [ -n "$responce" ]; then
		err="FAILED: Object comparison failed"
		let "failed = failed + 1"
		names="$name:$err; $names"
		continue
	fi
}

check_osds_up() {
	responce=$($ceph_cmd osd tree | grep "down")
	if [ -n "$responce" ]; then
		err="FAILED: Not all osds are up"
		let "failed = failed + 1"
		names="$name:$err; $names"
		continue
	fi
}

# Prework
rule=$($ceph_cmd osd crush rule list | grep "erasure-code")
if [ -z "$rule" ]; then
	echo "Create erasure crush rule before start"
	$ceph_cmd osd crush rule create-erasure erasure-code
fi
# create pools
$ceph_cmd osd pool create $cs_pool 128 128 erasure default erasure-code 0 $cs_type
$ceph_cmd osd pool create $noncs_pool 128 128 erasure
# create objects
mkdir -p test_obj
dd if=/dev/urandom of=test_obj/badobj bs=$test_obj_size count=1
dd if=/dev/zero of=test_obj/goodobj bs=$test_obj_size count=1
dd if=/dev/urandom of=/tmp/tmpobj bs=$test_obj_parts count=1
res_obj=""
for i in {1..$test_obj_parts_count}; do
	res_obj="/tmp/tmpobj $res_obj"
done
cat $res_obj > test_obj/middleobj
objs="test_obj/badobj test_obj/goodobj test_obj/middleobj"
# create test folder
mkdir -p "$test_folder"

# Tests
name="1. Object put/get verification to  erasure-code pool with compression"
echo "$name"
for obj in $objs; do
	delete_object $cs_pool test
	delete_object $cs_pool test2
	echo "Test object $obj"
	put_object $cs_pool "$obj" test
	check_lspool $cs_pool test
	get_object $cs_pool test "$test_folder/test"
	cmp_objects "$obj" "$test_folder/test"
	$rados_cmd -p $cs_pool create test2
	if [ $? -ne 0 ]; then
		err="FAILED: Cannot create object"
		let "failed = failed + 1"
		names="$name:$err; $names"
		continue
	fi
	check_lspool $cs_pool test2
	get_object $cs_pool test2 "$test_folder/test2"
	if [ -s test2 ]; then
		err="FAILED: File has wrong size"
		let "failed = failed + 1"
		names="$name:$err; $names"
		continue
	fi
	let "succeeded = succeeded + 1"
done

name="2. Object put to a pool with compression, compression disable followed by another object put"
echo "$name"
for obj in $objs; do
	delete_object $cs_pool test
	delete_object $cs_pool nc_test
	echo "Test object $obj"
	put_object $cs_pool "$obj" test
	$ceph_cmd osd pool set $cs_pool compression_type none
	put_object $cs_pool "$obj" nc_test
	get_object $cs_pool test "$test_folder/test1"
	cmp_objects "$obj" "$test_folder/test1"
	get_object $cs_pool nc_test "$test_folder/test2"
	cmp_objects "$test_folder/test1" "$test_folder/test2"
	let "succeeded = succeeded + 1"
done

name="3. Object put to a pool without compression, compression enable followed by another object put"
echo "$name"
for obj in $objs; do
	delete_object $cs_pool test
	delete_object $cs_pool nc_test
	echo "Test object $obj"
	$ceph_cmd osd pool set $cs_pool compression_type none
	put_object $cs_pool "$obj" nc_test
	$ceph_cmd osd pool set $cs_pool compression_type zlib
	put_object $cs_pool "$obj" test
	get_object $cs_pool test "$test_folder/test1"
	cmp_objects "$obj" "$test_folder/test1"
	get_object $cs_pool nc_test "$test_folder/test2"
	cmp_objects "$obj" "$test_folder/test2"
	let "succeeded = succeeded + 1"
done

name="4. Object put to a pool with compression, compression change followed by object retrieval"
echo "$name"
for obj in $objs; do
	delete_object $cs_pool test
	echo "Test object $obj"
	put_object $cs_pool "$obj" test
	$ceph_cmd osd pool set $cs_pool compression_type snappy
	get_object $cs_pool test "$test_folder/test1"
	cmp_objects "$obj" "$test_folder/test1"
	let "succeeded = succeeded + 1"
done

name="5. Verify compressed object access after pool rename"
echo "$name"
for obj in $objs; do
	delete_object $cs_pool test
	echo "Test object $obj"
	put_object $cs_pool "$obj" test
	check_lspool $cs_pool test
	$ceph_cmd osd pool rename $cs_pool "$cs_pool"1
	get_object "$cs_pool"1 test "$test_folder/test1"
	cmp_objects "$obj" "$test_folder/test1"
	$ceph_cmd osd pool rename "$cs_pool"1 $cs_pool
	let "succeeded = succeeded + 1"
done

name="6. Verify compressed object access after object copy"
echo "$name"
for obj in $objs; do
	delete_object $cs_pool test
	delete_object $cs_pool test1
	echo "Test object $obj"
	put_object $cs_pool "$obj" test
	check_lspool $cs_pool test
	$rados_cmd -p $cs_pool cp test test1
	if [ $? -ne 0 ]; then
		err="FAILED: Cannot copy object"
		let "failed = failed + 1"
		names="$name:$err; $names"
		continue
	fi
	get_object $cs_pool test1 "$test_folder/test1"
	cmp_objects "$obj" "$test_folder/test1"
	let "succeeded = succeeded + 1"
done

name="7. Rados clonedata refression"
echo "$name"
obj="test_obj/goodobj"
for pool in $cs_pool $noncs_pool; do
	echo "Test pool $pool"
	delete_object $pool test
	delete_object $pool test2
	$rados_cmd -p $pool put test "$obj" --object_locator some_locator
	if [ $? -ne 0 ]; then
		err="FAILED: Cannot put object with locator"
		let "failed = failed + 1"
		names="$name:$err; $names"
		continue
	fi
	$rados_cmd -p $pool create test2 --object_locator some_locator
	if [ $? -ne 0 ]; then
		err="FAILED: Cannot create object with locator"
		let "failed = failed + 1"
		names="$name:$err; $names"
		continue
	fi
	responce=$($rados_cmd -p $pool clonedata test test2 --object_locator some_locator 2>&1 | grep "not supported")
	if [ -z "$responce" ]; then
		err="FAILED: No expected error"
		let "failed = failed + 1"
		names="$name:$err; $names"
		continue
	fi
	let "succeeded = succeeded + 1"
done

name="8. Verify compressed object access after xattrs operations"
echo "$name"
for obj in $objs; do
	delete_object $cs_pool test
	echo "Test object $obj"
	put_object $cs_pool "$obj" test
	check_lspool $cs_pool test
	responce=$($rados_cmd -p $cs_pool listxattr test | grep "@ci")
	if [ -n "$responce" ]; then
		err="FAILED: Xattrs contains @ci"
		let "failed = failed + 1"
		names="$name:$err; $names"
		continue
	fi
	$rados_cmd -p $cs_pool setxattr test someattr someval
	if [ $? -ne 0 ]; then
		err="FAILED: Cannot set xattrs"
		let "failed = failed + 1"
		names="$name:$err; $names"
		continue
	fi
	responce=$($rados_cmd -p $cs_pool getxattr test someattr | grep "someval")
	if [ -z "$responce" ]; then
		err="FAILED: Xattrs doesn't contain added someval"
		let "failed = failed + 1"
		names="$name:$err; $names"
		continue
	fi
	$rados_cmd -p $cs_pool  rmxattr test someattr
	if [ $? -ne 0 ]; then
		err="FAILED: Cannot remove xattrs"
		let "failed = failed + 1"
		names="$name:$err; $names"
		continue
	fi
	get_object $cs_pool test "$test_folder/test1"
	cmp_objects "$obj" "$test_folder/test1"
	let "succeeded = succeeded + 1"
done

name="9. Verify compressed object access after omap operations"
echo "$name"
for obj in $objs; do
	delete_object $cs_pool test
	echo "Test object $obj"
	put_object $cs_pool "$obj" test
	check_lspool $cs_pool test
	responce=$($rados_cmd -p $cs_pool listomapkeys test | grep "@ci")
	if [ -n "$responce" ]; then
		err="FAILED: Omap keys contains @ci"
		let "failed = failed + 1"
		names="$name:$err; $names"
		continue
	fi
	$rados_cmd -p $cs_pool setomapval test someattr someval
	if [ $? -ne 0 ]; then
		err="FAILED: Cannot set omap val"
		let "failed = failed + 1"
		names="$name:$err; $names"
		continue
	fi
	responce=$($rados_cmd -p $cs_pool getomapval test someattr | grep "someval")
	if [ -z "$responce" ]; then
		err="FAILED: Omap val doesn't contain added someval"
		let "failed = failed + 1"
		names="$name:$err; $names"
		continue
	fi
	$rados_cmd -p $cs_pool rmomapkey test someattr
	if [ $? -ne 0 ]; then
		err="FAILED: Cannot remove omap val"
		let "failed = failed + 1"
		names="$name:$err; $names"
		continue
	fi
	get_object $cs_pool test "$test_folder/test1"
	cmp_objects "$obj" "$test_folder/test1"
	let "succeeded = succeeded + 1"
done

name="10. Regression testing against rados bench operation"
echo "$name"
for pool in $cs_pool $noncs_pool; do
	echo "Test pool $pool"
	$rados_cmd -p $pool bench 32 write --no-cleanup
	if [ $? -ne 0 ]; then
		err="FAILED: Rados bench failed"
		let "failed = failed + 1"
		names="$name:$err; $names"
		continue
	fi
	check_osds_up
	$rados_cmd -p $pool bench 32 seq
	if [ $? -ne 0 ]; then
		err="FAILED: Rados bench failed"
		let "failed = failed + 1"
		names="$name:$err; $names"
		continue
	fi
	check_osds_up
	$rados_cmd -p $pool bench 32 rand
	if [ $? -ne 0 ]; then
		err="FAILED: Rados bench failed"
		let "failed = failed + 1"
		names="$name:$err; $names"
		continue
	fi
	check_osds_up
	responce=$($rados_cmd -p $pool cleanup)
	if [ -n "$responce" ]; then
		err="FAILED: Cleanup failed"
		let "failed = failed + 1"
		names="$name:$err; $names"
		continue
	fi
	let "succeeded = succeeded + 1"
done

name="11. Rados truncate operation regression"
echo "$name"
obj="test_obj/goodobj"
for pool in $cs_pool $noncs_pool; do
	echo "Test pool $pool"
	delete_object $pool test
	delete_object $pool test_nc
	put_object $pool "$obj" test_nc
	put_object $pool "$obj" test
	responce=$($rados_cmd -p $pool truncate test 1 2>&1 | grep "not supported")
	if [ -z "$responce" ]; then
		err="FAILED: No expected error"
		let "failed = failed + 1"
		names="$name:$err; $names"
		continue
	fi
	let "succeeded = succeeded + 1"
done

name="12. Verify snapshot/rollback operations"
echo "$name"
obj="test_obj/goodobj"
for pool in $cs_pool $noncs_pool; do
	echo "Test pool $pool"
	delete_object $pool test
	put_object $pool "$obj" test
	$rados_cmd -p $pool mksnap snap1
	if [ $? -ne 0 ]; then
		err="FAILED: Rados mksnap failed"
		let "failed = failed + 1"
		names="$name:$err; $names"
		continue
	fi
	delete_object $pool test
	$rados_cmd -p $pool create test
	if [ $? -ne 0 ]; then
		err="FAILED: Cannot create object"
		let "failed = failed + 1"
		names="$name:$err; $names"
		continue
	fi
	$rados_cmd -p $pool rollback test snap1
	if [ $? -ne 0 ]; then
		err="FAILED: Rados rollback failed"
		let "failed = failed + 1"
		names="$name:$err; $names"
		continue
	fi
	get_object $pool test "$test_folder/test1"
	cmp_objects "$obj" "$test_folder/test1"
	let "succeeded = succeeded + 1"
done

delete_pool $cs_pool
delete_pool $noncs_pool
rm -rf "$test_folder"
rm -rf "test_obj"

echo "Report:"
echo "TOTAL:   $test_count"
echo "SUCCESS: $succeeded"
echo "FAILED:  $failed"
echo "Failed tests: $names"
