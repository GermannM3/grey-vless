#include <jni.h>

int hev_socks5_tunnel_main(const char *config_path, int tun_fd) {
    (void)config_path;
    (void)tun_fd;
    return -1;
}

void hev_socks5_tunnel_quit(void) {}

JNIEXPORT jint JNICALL
Java_com_grey_grey_1vless_HevBridge_nativeRun(JNIEnv *env, jclass clazz, jstring jpath, jint tun_fd) {
    (void)env;
    (void)clazz;
    (void)jpath;
    (void)tun_fd;
    return hev_socks5_tunnel_main(NULL, -1);
}

JNIEXPORT void JNICALL
Java_com_grey_grey_1vless_HevBridge_nativeStop(JNIEnv *env, jclass clazz) {
    (void)env;
    (void)clazz;
    hev_socks5_tunnel_quit();
}
