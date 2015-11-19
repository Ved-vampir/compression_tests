import os
import sys
import rbd
import rados
import random

from cluster import connect, create_pool
from logger import define_logger

logger = define_logger(__name__)


def test_volume(cluster, pool_name, size, vol_name="test"):
    ioctx = cluster.open_ioctx(pool_name)
    rbd_inst = rbd.RBD()
    rbd_inst.create(ioctx, vol_name, size)
    image = rbd.Image(ioctx, 'myimage')
    data = ''.join([chr(ord('0')+i%10) for i in range(0, 200)])
    image.write(data, 0)
    data1 = image.read(0, 200)
    logger.info("wtitten == read: %s", data == data1)
    image.close()
    ioctx.close()


def main(argv):
    conf = argv[1] if len(argv) > 1 else '/mnt/other/work/ceph_test/ceph/src/ceph.conf'
    pool_name = "obpool"

    cluster = connect(conf)
    # if not create_pool(cluster, pool_name, "zlib"):
    #     return -1

    logger.info("Test test_volume started")
    if test_volume(cluster, pool_name):
        logger.info("Test failed, exit")
        cluster.shutdown()
        return -1

    cluster.shutdown()


if __name__ == '__main__':
    exit(main(sys.argv))
