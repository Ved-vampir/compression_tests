#/bin/bash -x

ceph_cmd="./ceph"
test_count=9
names=""
failed=0
succeeded=0

create_erasure_pool() {
	pool_name=$1
	compression_type=$2
	responce=$($ceph_cmd osd pool create $pool_name 12 12 erasure default erasure-code 0 $compression_type 2>&1)
	ok=$(echo "$responce" | grep "created")
	err=$(echo "$responce" | grep "Error EIO")
	if [ -z "$ok" ]; then
		if [ -z "$err" ]; then
			return 2
		else
			return 1
		fi
	else
		return 0
	fi
}

delete_pool() {
	pool_name=$1
	$ceph_cmd osd pool delete $pool_name $pool_name --yes-i-really-really-mean-it
}

# Prework
rule=$($ceph_cmd osd crush rule list | grep "erasure-code")
if [ -z "$rule" ]; then
	echo "Create erasure crush rule before start"
	$ceph_cmd osd crush rule create-erasure erasure-code
fi

# Tests
name="1. Invalid compression method name when creating erasure-code pool with compression"
echo "$name"
create_erasure_pool test badname
if [ $? -ne 1 ]; then
	echo "FAILED: There is not expected error"
	let "failed = failed + 1"
	names="$name; $names"
else
	let "succeeded = succeeded + 1"
fi

name="2. Valid compression method name when creating erasure-code pool with compression"
echo "$name"
create_erasure_pool test zlib
if [ $? -ne 0 ]; then
	echo "FAILED: Pool wasn't created"
	let "failed = failed + 1"
	names="$name; $names"
else
	responce=$($ceph_cmd osd pool get test compression_type | grep "zlib")
	if [ -z "$responce" ]; then
		echo "FAILED: Pool have wrong compression type"
		let "failed = failed + 1"
		names="$name; $names"
	else
		let "succeeded = succeeded + 1"
	fi
	delete_pool test
fi

name="3. Creating erasure-coded pool without compression"
echo "$name"
create_erasure_pool test ""
if [ $? -ne 0 ]; then
	echo "FAILED: Pool wasn't created"
	let "failed = failed + 1"
	names="$name; $names"
else
	responce=$($ceph_cmd osd pool get test compression_type | sed -n -e 's/^.*compression_type: //p')
	if [ -z "$responce" ]; then
		let "succeeded = succeeded + 1"
	else
		echo "FAILED: Compression type is not empty" 
		let "failed = failed + 1"
		names="$name; $names"
	fi	
	delete_pool test
fi

name="4. Change compression method from valid to invalid"
echo "$name"
create_erasure_pool test zlib
if [ $? -ne 0 ]; then
	echo "FAILED: Pool wasn't created"
	let "failed = failed + 1"
	names="$name; $names"
else
	responce=$($ceph_cmd osd pool set test compression_type badname 2>&1 | grep "Error EIO")
	if [ -z "$responce" ]; then
		echo "FAILED: There is not expected error"
		let "failed = failed + 1"
		names="$name; $names"
	else
		$responce=$($ceph_cmd osd pool get test compression_type | grep "zlib")
		if [ -z "$responce" ]; then
			echo "FAILED: Compression type has not expected value"
			let "failed = failed + 1"
			names="$name; $names"
		else
			let "succeeded = succeeded + 1"
		fi
	fi
	delete_pool test
fi

name="5. Change compression method from valid to valid"
echo "$name"
create_erasure_pool test zlib
if [ $? -ne 0 ]; then
	echo "FAILED: There is not expected error"
	let "failed = failed + 1"
	names="$name; $names"
else
	$ceph_cmd osd pool set test compression_type snappy
	if [ $? -ne 0 ]; then
		echo "FAILED: Cannot change compression type to legal value"
		let "failed = failed + 1"
		names="$name; $names"
	else
		responce=$($ceph_cmd osd pool get test compression_type | grep snappy)
		if [ -z "$responce" ]; then
			echo "FAILED: Compression type has not expected value"
			let "failed = failed + 1"
			names="$name; $names"
		else
			let "succeeded = succeeded + 1"
		fi
	fi
	delete_pool test
fi

name="6. Disable compression for a pool"
echo "$name"
create_erasure_pool test zlib
if [ $? -ne 0 ]; then
	echo "FAILED: Pool wasn't created"
	let "failed = failed + 1"
	names="$name; $names"
else
	$ceph_cmd osd pool set test compression_type none
	if [ $? -ne 0 ]; then
		echo "FAILED: Cannot disable compression"
		let "failed = failed + 1"
	else
		responce=$($ceph_cmd osd pool get test compression_type | grep "none")
		if [ -z "$responce" ]; then
			echo "FAILED: Compression type has not expected value"
			let "failed = failed + 1"
			names="$name; $names"
		else
			let "succeeded = succeeded + 1"
		fi
	fi
	delete_pool test
fi

name="7. Enable compression for erasure pool with no compression"
echo "$name"
create_erasure_pool etest ""
if [ $? -ne 0 ]; then
	echo "FAILED: Pool wasn't created"
	let "failed = failed + 1"
	names="$name; $names"
else
	responce=$($ceph_cmd osd pool get etest compression_type | sed -n -e 's/^.*compression_type: //p')
	if [ -z "$responce" ]; then
		$ceph_cmd osd pool set etest compression_type zlib
		if [ $? -ne 0 ]; then
			echo "FAILED: Cannot change compression type to legal value"
			let "failed = failed + 1"
			names="$name; $names"
		else
			responce=$($ceph_cmd osd pool get etest compression_type | grep zlib)
			if [ -z "$responce" ]; then
				echo "FAILED: Compression type has not expected value"
				let "failed = failed + 1"
				names="$name; $names"
			else
				let "succeeded = succeeded + 1"
			fi
		fi
	else
		echo "FAILED: Compression type is not empty"
		let "failed = failed + 1"
		names="$name; $names"
	fi
	delete_pool etest
fi
	
name="8. Attempt to enable compression for replicated pool"
echo "$name"
$ceph_cmd osd pool create rtest 12
responce=$($ceph_cmd osd pool set rtest compression_type zlib 2>&1 | grep "Error EINVAL")
if [ -z "$responce" ]; then
	echo "FAILED: There is not expected error"
	let "failed = failed + 1"
	names="$name; $names"
else
	let "succeeded = succeeded + 1"
	delete_pool rtest
fi

name="9. Check pool compression after pool rename"
echo "$name"
create_erasure_pool etest ""
if [ $? -ne 0 ]; then
	echo "FAILED: Pool wasn't created"
	let "failed = failed + 1"
	names="$name; $names"
else
	$ceph_cmd osd pool set etest compression_type zlib
	if [ $? -ne 0 ]; then
		echo "FAILED: Cannot change compression type to legal value"
		let "failed = failed + 1"
		names="$name; $names"
	else
		responce=$($ceph_cmd osd pool get etest compression_type | grep "zlib")
		if [ -z "$responce" ]; then
			echo "FAILED: Compression type has not expected value"
			let "failed = failed + 1"
			names="$name; $names"
		else
			$ceph_cmd osd pool rename etest etest1
			if [ $? -ne 0 ]; then
				echo "FAILED: Cannot rename pool"
				let "failed = failed + 1"
				names="$name; $names"
			else
				responce=$($ceph_cmd osd pool get etest1 compression_type | grep "zlib")
				if [ -z "$responce" ]; then
					echo "FAILED: Compression type has not expected value"
					let "failed = failed + 1"
					names="$name; $names"
				else
					$ceph_cmd osd pool set etest1 compression_type snappy
					if [ $? -ne 0 ]; then
						echo "FAILED: Cannot change compression type to legal value"
						let "failed = failed + 1"
						names="$name; $names"
					else
						responce=$($ceph_cmd osd pool get etest1 compression_type | grep "snappy")
						if [ -z "$responce" ]; then
							echo "FAILED: Compression type has not expected value"
							let "failed = failed + 1"
							names="$name; $names"
						else
							let "succeeded = succeeded + 1"
						fi
					fi
				fi
				delete_pool etest1
			fi
		fi
	fi
	delete_pool etest
fi

echo "Report:"
echo "TOTAL:   $test_count"
echo "SUCCESS: $succeeded"
echo "FAILED:  $failed"
echo "Failed tests: $names"
