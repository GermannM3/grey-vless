#include <jni.h>
#include "hev-main.h"

JNIEXPORT jint JNICALL
Java_com_grey_grey_1vless_HevBridge_nativeRun(JNIEnv *env, jclass clazz, jstring jpath, jint tun_fd) {
    const char *path = (*env)->GetStringUTFChars(env, jpath, NULL);
    if (path == NULL) {
        return -1;
    }
    int res = hev_socks5_tunnel_main(path, tun_fd);
    (*env)->ReleaseStringUTFChars(env, jpath, path);
    return res;
}

JNIEXPORT void JNICALL
Java_com_grey_grey_1vless_HevBridge_nativeStop(JNIEnv *env, jclass clazz) {
    (void)env;
    (void)clazz;
    hev_socks5_tunnel_quit();
}
