// Xi 2026-10-10: calls composer's QService notifyCallback (commands 300/301) to see whether hbm_enable changes.
#include <binder/IServiceManager.h>
#include <binder/ProcessState.h>
#include <binder/IBinder.h>
#include <binder/Parcel.h>
#include <cstdio>
#include <cstdlib>

using namespace android;

int main(int argc, char** argv) {
    ProcessState::initWithDriver("/dev/vndbinder");
    sp<IServiceManager> sm = defaultServiceManager();
    if (sm == nullptr) { printf("manager NULL\n"); return 1; }

    sp<IBinder> q = sm->checkService(String16("display.qservice"));
    printf("display.qservice = %s\n", q ? "found" : "NOT FOUND");
    if (q == nullptr) return 1;
    fflush(stdout);

    int cmd = (argc > 1) ? atoi(argv[1]) : 300;
    int a   = (argc > 2) ? atoi(argv[2]) : 0;
    int b   = (argc > 3) ? atoi(argv[3]) : 0;

    Parcel data, reply;
    data.writeInterfaceToken(String16("android.display.IQService"));
    data.writeInt32(a);
    data.writeInt32(b);
    status_t st = q->transact(cmd, data, &reply);
    printf("transact(code=%d, [%d,%d]) -> status=%d\n", cmd, a, b, st);
    printf("reply: dataSize=%zu\n", reply.dataSize());
    return 0;
}
