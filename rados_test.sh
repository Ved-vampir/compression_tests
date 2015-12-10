#/bin/bash -x

ceph_cmd="./ceph"
rados_cmd="./rados"
cs_pool="obpool"
noncs_pool="ec_no_compression_pool"
cs_type="zlib"
test_obj_size="100M"
test_obj_parts="25M"
test_obj_parts_count=4
test_count=9
names=""
failed=0
succeeded=0

delete_pool() {
	pool_name=$1
	$ceph_cmd osd pool delete $pool_name $pool_name --yes-i-really-really-mean-it
}

delete_object() {
	pool_name=$1
	obj_name=$2
	$rados_cmd -p $pool_name rm $obj_name
}

# functions for use in cycle
put_object() {
	$rados_cmd -p $1 put $3 $2
	if [ $? -ne 0 ]; then
		err="FAILED: Cannot put object"
		let "failed = failed + 1"
		names="$name:$err; $names"
		continue
	fi
}

check_lspool() {
	responce=$($rados_cmd -p $1 ls | grep $2)
	if [ -z "$responce" ]; then
		err="FAILED: Object is not in pool"
		let "failed = failed + 1"
		names="$name:$err; $names"
		continue
	fi
}

get_object() {
	$rados_cmd -p $1 get $2 $3
	if [ $? -ne 0 ]; then
		err="FAILED: Cannot get object"
		let "failed = failed + 1"
		names="$name:$err; $names"
		continue
	fi
}

cmp_objects() {
	responce=$(cmp $1 $2)
	if [ -n "$responce" ]; then
		err="FAILED: Object comparison failed"
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

# Tests
name="1. Object put/get verification to  erasure-code pool with compression"
echo "$name"
for obj in objs; do
	delete_object $cs_pool test
	delete_object $cs_pool test2
	echo "Test object $obj"
	put_object $cs_pool obj test
	check_lspool $cs_pool test
	get_object $cs_pool test test
	cmp_objects $obj test
	$rados_cmd -p $cs_pool create test2
	if [ $? -ne 0 ]; then
		err="FAILED: Cannot create object"
		let "failed = failed + 1"
		names="$name:$err; $names"
		continue
	fi
	check_lspool $cs_pool test2
	get_object $cs_pool test2 test2
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
for obj in objs; do
	delete_object $cs_pool test
	delete_object $cs_pool nc_test
	echo "Test object $obj"
	put_object $cs_pool $obj test
	$ceph_cmd osd pool set $cs_pool compression_type none
	put_object $cs_pool $obj nc_test
	get_object $cs_pool test test1
	cmp_objects $obj test1
	get_object $cs_pool nc_test test2
	cmp_objects test1 test2
	let "succeeded = succeeded + 1"
done

name="3. Object put to a pool without compression, compression enable followed by another object put"
echo "$name"
for obj in objs; do
	delete_object $cs_pool test
	delete_object $cs_pool nc_test
	echo "Test object $obj"
	$ceph_cmd osd pool set $cs_pool compression_type none
	put_object $cs_pool $obj nc_test
	$ceph_cmd osd pool set $cs_pool compression_type zlib
	put_object $cs_pool $obj test
	get_object $cs_pool test test1
	cmp_objects $obj test1
	get_object $cs_pool nc_test test2
	cmp_objects $obj test2
	let "succeeded = succeeded + 1"
done

name="4. Object put to a pool with compression, compression change followed by object retrieval"
echo "$name"
for obj in objs; do
	delete_object $cs_pool test
	echo "Test object $obj"
	put_object $cs_pool $obj test
	$ceph_cmd osd pool set $cs_pool compression_type snappy
	get_object $cs_pool test test1
	cmp_objects $obj test1
	let "succeeded = succeeded + 1"
done

name="5. Verify compressed object access after pool rename"
echo "$name"
for obj in objs; do
	delete_object $cs_pool test
	echo "Test object $obj"
	put_object $cs_pool $obj test
	check_lspool $cs_pool test
	$ceph_cmd osd pool rename $cs_pool "$cs_pool"1
	get_object "$cs_pool"1 test test1
	cmp_objects $obj test1
	$ceph_cmd osd pool rename "$cs_pool"1 $cs_pool
	let "succeeded = succeeded + 1"
done

name="6. Verify compressed object access after object copy"
echo "$name"
for obj in objs; do
	delete_object $cs_pool test
	delete_object $cs_pool test1
	echo "Test object $obj"
	put_object $cs_pool $obj test
	check_lspool $cs_pool test
	$rados_cmd -p $cs_pool cp test test1
	if [ $? -ne 0 ]; then
		err="FAILED: Cannot copy object"
		let "failed = failed + 1"
		names="$name:$err; $names"
		continue
	fi
	get_object $cs_pool test1 test1
	cmp_objects $obj test1
	let "succeeded = succeeded + 1"
done

name="7. Rados clonedata refression"
echo "$name"
for pool in $cs_pool $noncs_pool; do
	echo "Test pool $pool"
	delete_object $pool test
	$rados_cmd -p $pool put 
	let "succeeded = succeeded + 1"
done

echo "Report:"
echo "TOTAL:   $test_count"
echo "SUCCESS: $succeeded"
echo "FAILED:  $failed"
echo "Failed tests: $names"
