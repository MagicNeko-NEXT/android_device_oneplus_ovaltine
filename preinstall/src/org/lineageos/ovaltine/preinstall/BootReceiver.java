/*
 * SPDX-License-Identifier: Apache-2.0
 */

package org.lineageos.ovaltine.preinstall;

import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageInstaller;
import android.content.pm.PackageManager;
import android.util.Log;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class BootReceiver extends BroadcastReceiver {
    private static final String TAG = "OvaltinePreinstall";
    static final String PREFS_NAME = "preinstall";
    static final String KEY_APERTURE_DONE = "aperture_done";
    static final String APERTURE_PKG = "org.lineageos.aperture";
    private static final String APERTURE_APK = "/product/etc/preinstall/Aperture.apk";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (!Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())) {
            return;
        }

        final Context appCtx = context.getApplicationContext();
        final SharedPreferences prefs = appCtx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        if (prefs.getBoolean(KEY_APERTURE_DONE, false)) {
            disableSelf(appCtx);
            return;
        }

        if (isInstalled(appCtx.getPackageManager(), APERTURE_PKG)) {
            prefs.edit().putBoolean(KEY_APERTURE_DONE, true).apply();
            disableSelf(appCtx);
            return;
        }

        final File apkFile = new File(APERTURE_APK);
        if (!apkFile.isFile()) {
            Log.w(TAG, "Missing preinstall APK: " + APERTURE_APK);
            return;
        }

        final PendingResult pendingResult = goAsync();
        final ExecutorService executor = Executors.newSingleThreadExecutor();
        executor.execute(() -> {
            try {
                installAperture(appCtx, apkFile);
            } catch (Exception e) {
                Log.e(TAG, "Failed to install Aperture", e);
            } finally {
                pendingResult.finish();
                executor.shutdown();
            }
        });
    }

    private static void installAperture(Context context, File apkFile) throws Exception {
        final PackageInstaller installer = context.getPackageManager().getPackageInstaller();
        final PackageInstaller.SessionParams params =
                new PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL);
        params.setAppPackageName(APERTURE_PKG);
        params.setInstallReason(PackageManager.INSTALL_REASON_DEVICE_SETUP);

        final int sessionId = installer.createSession(params);
        try (PackageInstaller.Session session = installer.openSession(sessionId)) {
            try (InputStream in = new FileInputStream(apkFile);
                 OutputStream out = session.openWrite("Aperture.apk", 0, apkFile.length())) {
                byte[] buf = new byte[65536];
                int n;
                while ((n = in.read(buf)) > 0) {
                    out.write(buf, 0, n);
                }
                session.fsync(out);
            }

            final Intent resultIntent = new Intent(context, InstallResultReceiver.class);
            final PendingIntent callback = PendingIntent.getBroadcast(
                    context,
                    sessionId,
                    resultIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_MUTABLE);
            session.commit(callback.getIntentSender());
        }
    }

    private static boolean isInstalled(PackageManager pm, String pkg) {
        try {
            pm.getPackageInfo(pkg, 0);
            return true;
        } catch (PackageManager.NameNotFoundException e) {
            return false;
        }
    }

    static void disableSelf(Context context) {
        context.getPackageManager().setComponentEnabledSetting(
                new ComponentName(context, BootReceiver.class),
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP);
    }
}
