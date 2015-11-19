import rados

from execute import execute
from logger import define_logger

logger = define_logger(__name__)



def start_dev_cluster(mon=1, osd=3, mds=0):
    cmd = "MON={0} OSD={1} MDS={2} ./vstart.sh -l -n -d"
    try:
        execute(cmd)
    except:
        logger.error("Cannot start cluster!")


def connect(conffile):
    """ Connect to cluster """
    cluster = rados.Rados(conffile=conffile)
    cluster.connect()
    logger.info("Cluster ID: %s", cluster.get_fsid())
    return cluster


def create_pool(cluster, pool_name, compression_type, tier=True, pg_num=32, pgp_num=32):
    """ Create erasure pool pool_name with compression compression_type """
    if cluster.pool_exists(pool_name):
        cluster.delete_pool(pool_name)
    if tier and cluster.pool_exists(pool_name+"_tier"):
        cluster.delete_pool(pool_name+"_tier")

    try:
        cmds = ["./ceph osd pool create {0} {1} {2} erasure".format(pool_name,
                                                                    pg_num,
                                                                    pgp_num),
                "./ceph osd pool set {0} compression_type {1}".format(pool_name,
                                                                      compression_type)
               ]
        if tier:
            cmds.extend(["./ceph osd pool create {0}_tier {1} {2}".format(pool_name,
                                                                          pg_num,
                                                                          pgp_num),
                         "./ceph osd tier add {0} {0}_tier".format(pool_name),
                         "./ceph osd tier cache-mode {0}_tier writeback".format(pool_name),
                         "./ceph osd tier set-overlay {0} {0}_tier".format(pool_name)
                        ])

        for cmd in cmds:
            res = execute(cmd)
            logger.debug(res)
    except Exception as ex:
        logger.error("%s failed: %s", cmd, ex.message())
        return False
    return True

