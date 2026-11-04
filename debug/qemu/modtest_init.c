#define _GNU_SOURCE
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/reboot.h>
#include <sys/utsname.h>
static char cmd[4096];
static void cat(const char *p){char b[4096];int f=open(p,O_RDONLY);if(f<0){printf("(%s: %s)\n",p,strerror(errno));return;}int n;while((n=read(f,b,sizeof b))>0)fwrite(b,1,n,stdout);close(f);fflush(stdout);}
static int skipped(const char*n){char k[300];snprintf(k,sizeof k,",%.280s,",n);char*s=strstr(cmd,"skip=");if(!s)return 0;char b[3000];snprintf(b,sizeof b,",%s",s+5);char*e=strpbrk(b," \n");if(e)*e=0;strcat(b,",");return strstr(b,k)!=NULL;}
int main(void){
 mkdir("/dev",0755);mkdir("/proc",0755);mkdir("/sys",0755);
 mount("devtmpfs","/dev","devtmpfs",0,0);mount("proc","/proc","proc",0,0);mount("sysfs","/sys","sysfs",0,0);
 int c=open("/dev/console",O_RDWR);if(c>=0){dup2(c,0);dup2(c,1);dup2(c,2);}
 setvbuf(stdout,0,_IOLBF,0);
 struct utsname u;uname(&u);printf("QT init pid=%d kernel=%s %s\n",getpid(),u.release,u.machine);
 int f=open("/proc/cmdline",O_RDONLY);int n=read(f,cmd,sizeof cmd-1);if(n>0)cmd[n]=0;close(f);
 printf("QT cmdline: %s",cmd);
 printf("QT bootconfig:\n");cat("/proc/bootconfig");
 printf("QT pstore fs:");cat("/proc/filesystems");
 printf("QT SMOKE_OK\n");
 FILE*o=fopen("/order.txt","r");
 if(o&&strstr(cmd,"qt=mods")){char l[300];int ok=0,fail=0,skip=0;
  while(fgets(l,sizeof l,o)){l[strcspn(l,"\n")]=0;if(!*l)continue;
   if(skipped(l)){printf("QT SKIP %s\n",l);skip++;continue;}
   char p[400];snprintf(p,sizeof p,"/m/%s",l);
   printf("QT LOAD %s\n",l);fflush(stdout);
   int m=open(p,O_RDONLY);if(m<0){printf("QT RES %s missing\n",l);fail++;continue;}
   long r=syscall(SYS_finit_module,m,"",0);int e=errno;close(m);
   if(r==0){ok++;printf("QT RES %s ok\n",l);}else{fail++;printf("QT RES %s err=%d %s\n",l,e,strerror(e));}
  }
  printf("QT MODS_DONE ok=%d fail=%d skip=%d\n",ok,fail,skip);
  sleep(20);
  printf("QT lsmod:\n");cat("/proc/modules");
  printf("QT SETTLE_OK\n");
 }
 sync();reboot(RB_POWER_OFF);for(;;)pause();
}
