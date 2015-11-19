import os
import sys
import rados
import random

from cluster import connect, create_pool
from logger import define_logger

logger = define_logger(__name__)




def test_pool(cluster, pool_name, data_func, ob_name="test"):
    """ Test pool pool_name with objects 
        data_func(n) must return string with n bytes """
    # static lens
    ob_len = [1, 5, 3*1024, 7*1024]
    # random lens
    random.seed()
    ob_len.extend([random.randint(3, 1024*1024*100) for i in range(5)])
    # calc lens
    mult = [1, 2, 3, 5, 32, 4*256, 8*256, 2*8*256, 3*8*256]
    for i in mult:
        x = i*4*1024
        ob_len.append(x - 1)
        ob_len.append(x)
        ob_len.append(x + 1)

    bl_size = [i*4*1024 for i in mult]
    # bl_size.append(1)
    bl_size.append(random.randrange(4*1024, 1024*1024*100, 4*1024))

    ioctx = cluster.open_ioctx(pool_name)

    old = ob_name
    for l in ob_len:
        logger.info("Test for object size %i started", l)
        for bl in bl_size:
            if bl > l and l >= 4*1024:
                continue
            ob_name = old + str(l) + str(bl)
            try:
                ioctx.remove_object(ob_name)
            except:
                pass
            # write object
            logger.info("Write in blocks %i started", bl)
            off = 0
            tl = l
            wdata = ''
            # first block for no-tier pool
            cur = min(bl, tl)
            data = data_func(cur)
            wdata += data
            ioctx.write(ob_name, data)
            off += cur
            tl -= cur
            while tl > 0:
                cur = min(bl, tl)
                data = data_func(cur)
                wdata += data
                ioctx.write(ob_name, data, off)
                off += cur
                tl -= cur
            # test object
            real_len, _ = ioctx.stat(ob_name)
            if real_len != l:
                    logger.error("blsize=%i, flen=%i, object stat len=%i", bl, l, real_len)
                    return -1
            else:
                logger.debug("object stat is equal to %i", l)
            # read object
            logger.info("Read started")
            for rbl in ob_len:
                if rbl > l:
                    continue
                # forward
                off = 0
                tl = l
                logger.debug("Forward read in blocks %i", rbl)
                while tl > 0:
                    cur = min(rbl, tl)
                    rdata = ioctx.read(ob_name, cur, off)
                    if len(rdata) != cur:
                        logger.error("forward read, blsize=%i, flen=%i, cannot read %i, read = %i", bl, l, cur, len(rdata))
                        return -1
                    else:
                        logger.debug("forward read, blsize=%i, flen=%i, read %i, more %i", bl, l, cur, tl - cur)
                    if rdata != wdata[off:off+cur]:
                        logger.error("forward read, blsize=%i, flen=%i, data slice is different", bl, l)
                        logger.debug("read %s, expected %s", rdata, wdata[off:off+cur])
                        return -1
                    else:
                        logger.debug("forward read, blsize=%i, flen=%i, data slice is equal", bl, l)
                    off += cur
                    tl -= cur
                # backward
                logger.debug("Backward read in blocks %i", rbl)
                off = l - rbl
                tl = l
                while tl > 0:
                    cur = min(rbl, tl)
                    rdata = ioctx.read(ob_name, cur, off)
                    if len(rdata) != cur:
                        logger.error("backward read, blsize=%i, flen=%i, cannot read %i, read = %i", bl, l, cur, len(rdata))
                        return -1
                    else:
                        logger.debug("backward read, blsize=%i, flen=%i, read %i, more %i", bl, l, cur, tl - cur)
                    if rdata != wdata[off:off+cur]:
                        logger.error("backward read, blsize=%i, flen=%i, data slice is different", bl, l)
                        logger.debug("read %s, expected %s", rdata, wdata[off:off+cur])
                        return -1
                    else:
                        logger.debug("backward read, blsize=%i, flen=%i, data slice is equal", bl, l)
                    off -= cur
                    off = max(off, 0)
                    tl -= cur
            # remove object
            if not ioctx.remove_object(ob_name):
                logger.warning("Cannot delete object")

    ioctx.close()



def main(argv):
    conf = argv[1] if len(argv) > 1 else '/mnt/other/work/ceph_test/ceph/src/ceph.conf'
    pool_name = "test"

    cluster = connect(conf)
    # if not create_pool(cluster, pool_name, "zlib"):
    #     return -1

    datafuncs = [lambda n: ''.join([chr(ord('0')+i%10) for i in range(0, n)]), # for content test
                 lambda n: ''.zfill(n),
                 os.urandom,
                 lambda n: os.urandom(n/2).center(n, '\x00')]

    for i, datafunc in enumerate(datafuncs):
        logger.info("Test test_pool by %i func started", i)
        if test_pool(cluster, pool_name, datafunc):
            logger.info("Test failed, exit")
            cluster.shutdown()
            return -1

    cluster.shutdown()


if __name__ == '__main__':
    exit(main(sys.argv))
