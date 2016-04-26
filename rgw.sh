#/bin/bash -x

# objects stat
test_obj_types=4
test_obj_size=(524288 524292 100K 100M 1024M)
test_obj_parts=(131072 131073 25K 25M 256M)
test_obj_parts_count=4
test_obj_begin=(500000 524289 2 524300 1048600)
test_obj_end=(524288 524290 10 1048600 2000000)
# swift user info
host="http://localhost:8000"
user="test:tester"
pass="testing"
# tests stat
test_folder="tmp_test_folder"
test_count=2
names=""
failed=0

# get creds for curl
token=$(curl -i -H "X-Auth-User: $user" -H "X-Auth-Key: $pass" $host/auth/v1.00 | grep X-Auth-Token | sed 's/X-Auth-Token: //')
echo "Token for curl was get: $token"

# create test folder
mkdir -p "$test_folder"
objs="badobj goodobj middleobj"

# func (folder test_obj_size test_obj_parts test_obj_parts_count)
create_objects() {
    mkdir -p test_obj/"$1"
    dd if=/dev/urandom of=test_obj/"$1"/badobj bs=$2 count=1
    dd if=/dev/zero of=test_obj/"$1"/goodobj bs=$2 count=1
    dd if=/dev/urandom of=/tmp/tmpobj bs=$3 count=1
    res_obj=""
    for k in $(seq 1 $4); do
        res_obj="/tmp/tmpobj $res_obj"
    done
    cat $res_obj > test_obj/"$1"/middleobj
}

# func (cont obj)
upload_object() {
    swift -A $host/auth -U $user -K $pass upload cont$1 $2
    if [ $? -ne 0 ]; then
        err="FAILED: Cannot put object $1/$2"
        let "failed = failed + 1"
        names="$name:$err; \n$names"
        continue
    fi
}

#func (cont obj)
download_object() {
    responce=$(swift -A $host/auth -U $user -K $pass download cont$1 $2)
    if [ $? -ne 0 ]; then
        err="FAILED: Cannot get object $1/$2: $responce"
        let "failed = failed + 1"
        names="$name:$err; \n$names"
        continue
    fi
    if [ -n "$(echo "$responce" | grep "error")" ]; then
        err="FAILED: Error in download $1/$2: $responce"
        let "failed = failed + 1"
        names="$name:$err; \n$names"
        continue
    fi
    if [ -n "$(echo "$responce" | grep "mismatch")" ]; then
        err="FAILED: Md5 mismatch in download $1/$2"
        let "failed = failed + 1"
        names="$name:$err; \n$names"
        continue
    fi
}

# func (obj1 obj2)
cmp_objects() {
    responce=$(cmp "$1" "$2" 2>&1)
    if [ -n "$responce" ]; then
        err="FAILED: Object comparison failed $1/$2"
        let "failed = failed + 1"
        names="$name:$err; \n$names"
        continue
    fi
}

# func (begin end cont obj_name output_name)
get_object_part() {
    curl -X GET -H "X-Auth-Token: $token" -H "Range: bytes=$1-$2"  $host/swift/v1/cont$3/$4 > "$5"
    if [ $? -ne 0 ]; then
        err="FAILED: Cannot get part of object $3/$4"
        let "failed = failed + 1"
        names="$name:$err; \n$names"
        continue
    fi
}

# func (begin end folder in_obj out_obj)
create_object_part() {
    let "len = $2 - $1 + 1"
    dd skip=$1 count=$len if=../test_obj/"$3"/$4 of=$5 bs=1
}

# Prework
echo "Prework"
mkdir -p test_obj
for i in $(seq 0 $test_obj_types); do
    create_objects $i ${test_obj_size[$i]} ${test_obj_parts[$i]} $test_obj_parts_count
    cd test_obj/$i
    for obj in $objs; do
        upload_object $i $obj
    done
    cd ../..
done
cd "$test_folder"

# Tests
echo "Tests"

name="Test 1. Object put/get verification with compression"
echo "$name"
for i in $(seq 0 $test_obj_types); do    
    for obj in $objs; do
        download_object $i $obj
        cmp_objects ../test_obj/"$i"/$obj $obj
        rm $obj
    done
done

name="Test 2. Object put/parted get verification with compression"
echo "$name"
for i in $(seq 0 $test_obj_types); do
    for obj in $objs; do
        get_object_part ${test_obj_begin[$i]} ${test_obj_end[$i]} $i $obj "c$obj"
        create_object_part ${test_obj_begin[$i]} ${test_obj_end[$i]} $i $obj "d$obj"
        cmp_objects "c$obj" "d$obj"
        rm "c$obj" "d$obj"
    done
done

echo "Report:"

if [ -z $failed ]; then
    echo "No failed tests, remove tested data"
    cd ..
    rm -rf "$test_folder"
    rm -rf "test_obj"
fi

echo "TOTAL:   $test_count"
echo "FAILED:  $failed"
echo "Failed tests: $names"
