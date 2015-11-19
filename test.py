import rados, sys
from time import sleep

cluster = rados.Rados(conffile='/mnt/other/work/iceph/ceph/src/ceph.conf')

cluster.connect()
print "\nCluster ID: " + cluster.get_fsid()


ioctx = cluster.open_ioctx('ec1') #cached
try:
    ioctx.remove_object("pyobject1")
except:
    pass

s=''
l = 10*1024*1024
s=s.zfill(l)
print len(s)
print "Write=", ioctx.write("pyobject1", s)

#ioctx.remove_object("pyobject")

ioctx.close()
