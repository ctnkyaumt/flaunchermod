/*
 * FLaunchermod
 * Copyright (C)
 * 2026 - ctnkyaumt
 * Forked from: 2021  Étienne Fesser
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

package me.efesser.flauncher

import android.content.Context
import android.os.Build
import io.github.muntashirakon.adb.AbsAdbConnectionManager
import java.io.File
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.PrivateKey
import java.security.PublicKey
import java.security.cert.Certificate
import java.security.cert.CertificateFactory
import java.security.spec.PKCS8EncodedKeySpec
import java.util.Date
import java.util.Random
import sun.security.x509.AlgorithmId
import sun.security.x509.CertificateAlgorithmId
import sun.security.x509.CertificateExtensions
import sun.security.x509.CertificateIssuerName
import sun.security.x509.CertificateSerialNumber
import sun.security.x509.CertificateSubjectName
import sun.security.x509.CertificateValidity
import sun.security.x509.CertificateVersion
import sun.security.x509.CertificateX509Key
import sun.security.x509.KeyIdentifier
import sun.security.x509.PrivateKeyUsageExtension
import sun.security.x509.SubjectKeyIdentifierExtension
import sun.security.x509.X500Name
import sun.security.x509.X509CertImpl
import sun.security.x509.X509CertInfo

/**
 * The launcher's identity as an ADB client.
 *
 * adbd authenticates clients by public key. The key pair is generated once and
 * kept in the app's private storage; the user authorises it once, either by
 * accepting the "Allow debugging?" dialog or by entering a pairing code, and
 * the device remembers it from then on.
 */
class AdbConnectionManager private constructor(context: Context) : AbsAdbConnectionManager() {

    companion object {
        private const val KEY_FILE = "adb_private.key"
        private const val CERTIFICATE_FILE = "adb_certificate.pem"
        private const val KEY_ALGORITHM = "RSA"
        private const val SIGNATURE_ALGORITHM = "SHA512withRSA"
        private const val KEY_SIZE = 2048

        /** Certificates the launcher issues itself; a long life avoids churn. */
        private const val VALIDITY_MS = 10L * 365 * 24 * 60 * 60 * 1000

        @Volatile
        private var instance: AdbConnectionManager? = null

        @Throws(Exception::class)
        fun getInstance(context: Context): AbsAdbConnectionManager =
            instance ?: synchronized(this) {
                instance ?: AdbConnectionManager(context.applicationContext).also { instance = it }
            }
    }

    private val privateKey: PrivateKey
    private val certificate: Certificate

    init {
        // Tells the library which handshake the device expects.
        api = Build.VERSION.SDK_INT

        val keyFile = File(context.filesDir, KEY_FILE)
        val certificateFile = File(context.filesDir, CERTIFICATE_FILE)

        val loaded = loadExisting(keyFile, certificateFile)
        if (loaded != null) {
            privateKey = loaded.first
            certificate = loaded.second
        } else {
            val generated = generate(keyFile, certificateFile)
            privateKey = generated.first
            certificate = generated.second
        }
    }

    private fun loadExisting(keyFile: File, certificateFile: File): Pair<PrivateKey, Certificate>? {
        if (!keyFile.exists() || !certificateFile.exists()) return null
        return try {
            val key = KeyFactory.getInstance(KEY_ALGORITHM)
                .generatePrivate(PKCS8EncodedKeySpec(keyFile.readBytes()))
            val cert = certificateFile.inputStream().use {
                CertificateFactory.getInstance("X.509").generateCertificate(it)
            }
            key to cert
        } catch (e: Exception) {
            // Corrupt or written by an older version; start over.
            null
        }
    }

    private fun generate(keyFile: File, certificateFile: File): Pair<PrivateKey, Certificate> {
        val keyPair = KeyPairGenerator.getInstance(KEY_ALGORITHM)
            .apply { initialize(KEY_SIZE) }
            .generateKeyPair()
        val certificate = selfSign(keyPair)

        keyFile.writeBytes(keyPair.private.encoded)
        certificateFile.writeBytes(certificate.encoded)
        return keyPair.private to certificate
    }

    private fun selfSign(keyPair: KeyPair): Certificate {
        val publicKey: PublicKey = keyPair.public
        val notBefore = Date()
        val notAfter = Date(System.currentTimeMillis() + VALIDITY_MS)
        val subject = X500Name("CN=FLauncher")

        val extensions = CertificateExtensions().apply {
            set(
                "SubjectKeyIdentifier",
                SubjectKeyIdentifierExtension(KeyIdentifier(publicKey).identifier),
            )
            set("PrivateKeyUsage", PrivateKeyUsageExtension(notBefore, notAfter))
        }

        val info = X509CertInfo().apply {
            set("version", CertificateVersion(CertificateVersion.V3))
            set(
                "serialNumber",
                CertificateSerialNumber(Random().nextInt() and Int.MAX_VALUE),
            )
            set("algorithmID", CertificateAlgorithmId(AlgorithmId.get(SIGNATURE_ALGORITHM)))
            set("subject", CertificateSubjectName(subject))
            set("key", CertificateX509Key(publicKey))
            set("validity", CertificateValidity(notBefore, notAfter))
            set("issuer", CertificateIssuerName(subject))
            set("extensions", extensions)
        }

        return X509CertImpl(info).apply { sign(keyPair.private, SIGNATURE_ALGORITHM) }
    }

    override fun getPrivateKey(): PrivateKey = privateKey

    override fun getCertificate(): Certificate = certificate

    override fun getDeviceName(): String = "FLauncher"
}
