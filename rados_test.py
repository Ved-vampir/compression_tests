import os
import sys
import rados
import random

from cluster import connect, create_pool
from logger import define_logger

logger = define_logger(__name__)




def test_pool(cluster, pool_name, datafunc_id, data_func, do_reduced_test, ob_name="test"):
    """ Test pool pool_name with objects 
        data_func(n) must return string with n bytes """
    # static lens
    if not do_reduced_test:
      ob_len = [1, 5, 761, 3*1024+1, 7*1024-1]
    else:
      ob_len = [ 761, 7*1024-1]


    # random lens
    if not do_reduced_test:
      random.seed()
      ob_len.extend([random.randint(3, 1024*1024*100) for i in range(5)])

    # calc lens
    if not do_reduced_test:
      mult = [1, 2, 5, 32, 1024, 2*1024, 4*1024, 5*1024]
    else:
      mult = [1, 32, 5*1024]

    for i in mult:
        x = i*4*1024
        ob_len.append(x - 1)
        ob_len.append(x)
        ob_len.append(x + 1)


    ob_len.sort()
    bl_size = [i*4*1024 for i in mult]

    if not do_reduced_test:
      bl_size.append(random.randrange(4*1024, 1024*1024*89, 4*1024))

    bl_size.sort()

    ioctx = cluster.open_ioctx(pool_name)
    logger.info( "Object sizes:" + str(ob_len) )
    logger.info( "Block sizes:" + str(bl_size) )
    old = ob_name
    for l in ob_len:
        logger.info(">>>>>>>> Testing for object size =  %i bytes, datafunc = %i", l, datafunc_id)
        for bl in bl_size:
            #if bl > l and l >= 4*1024:
            #    continue
            ob_name = old + str(l) + str(bl)
            try:
                ioctx.remove_object(ob_name)
            except:
                pass
            # write object
            logger.info(">>>>>>>>>> Writing (block size=%i bytes)...", bl)
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
                    logger.error(">>>>>>>>>> blsize=%i, flen=%i, object stat len=%i", bl, l, real_len)
                    return -1
            else:
                logger.debug(">>>>>>>>>> object size = %i", l)
            # read object
            for rbl in ob_len:
                if (rbl > l) or ( rbl<256 and l>8*1024) or ( (rbl<4*4096 and rbl <> 4096 ) and l>=4*1024*1024): # do skip very small reads for large objects to speedup the process, leaving 4K read for any object size
                    continue
                # forward
                off = 0
                tl = l
                logger.info(">>>>>>>>>> Read, block size %i bytes", rbl)
                while tl > 0:
                    cur = min(rbl, tl)
                    rdata = ioctx.read(ob_name, cur, off)
                    if len(rdata) != cur:
                        logger.error(">>>>>>>>>> forward read, blsize=%i, flen=%i, cannot read %i, read = %i", bl, l, cur, len(rdata))
                        return -1
                    else:
                        logger.debug(">>>>>>>>>> forward read, blsize=%i, flen=%i, read %i, more %i", bl, l, cur, tl - cur)
                    if rdata != wdata[off:off+cur]:
                        logger.error(">>>>>>>>>> forward read, blsize=%i, flen=%i, data slice is different", bl, l)
                        logger.debug(">>>>>>>>>> read %s, expected %s", rdata, wdata[off:off+cur])
                        return -1
                    else:
                        logger.debug(">>>>>>>>>> forward read, blsize=%i, flen=%i, data slice is equal", bl, l)
                    off += cur
                    tl -= cur
                # backward
                logger.debug(">>>>>>>>>> Reverse read, block size =  %i bytes", rbl)
                off = l - rbl
                tl = l
                while tl > 0:
                    cur = min(rbl, tl)
                    rdata = ioctx.read(ob_name, cur, off)
                    if len(rdata) != cur:
                        logger.error(">>>>>>>>>> backward read, blsize=%i, flen=%i, cannot read %i, read = %i", bl, l, cur, len(rdata))
                        return -1
                    else:
                        logger.debug(">>>>>>>>>> backward read, blsize=%i, flen=%i, read %i, more %i", bl, l, cur, tl - cur)
                    if rdata != wdata[off:off+cur]:
                        logger.error(">>>>>>>>>> backward read, blsize=%i, flen=%i, data slice is different", bl, l)
                        logger.debug(">>>>>>>>>> read %s, expected %s", rdata, wdata[off:off+cur])
                        return -1
                    else:
                        logger.debug(">>>>>>>>>> backward read, blsize=%i, flen=%i, data slice is equal", bl, l)
                    off -= cur
                    off = max(off, 0)
                    tl -= cur
            # remove object
            if not ioctx.remove_object(ob_name):
                logger.warning(">>>>>>>>>> Cannot delete object")
            # do not repeat writes that cover all the object more than once
            if bl > l: 
              break


    ioctx.close()



def main(argv):
    conf = argv[1] if len(argv) > 1 else '/mnt/other/work/ceph_test/ceph/src/ceph.conf'
    do_reduced_test = argv[2] == '/reduced' if len(argv)>2 else False
    pool_name = "test"
    cluster = connect(conf)
    # if not create_pool(cluster, pool_name, "zlib"):
    #     return -1

    datafuncs = [lambda n: ''.join([chr(ord('0')+i%10) for i in range(0, n)]), # for content test
                 lambda n: ''.zfill(n),
                 os.urandom,
                 lambda n: os.urandom(n/2).center(n, '\x00')]

    for i, datafunc in enumerate(datafuncs):
        logger.info(">>>>>> Testing datafunc  %i ... ", i)
        if test_pool(cluster, pool_name, i, datafunc, do_reduced_test):
            logger.error(">>>>>> Test failed, exit")
            cluster.shutdown()
            return -1
        logger.info(">>>>>> Testing datafunc  %i completed", i)

    cluster.shutdown()


if __name__ == '__main__':
    exit(main(sys.argv))
