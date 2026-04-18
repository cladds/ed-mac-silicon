// mel-cred-helper: precompute the DPAPI-encrypted .cred file that
// min-ed-launcher expects, so we can skip the broken interactive prompt
// under Wine. Must run under Wine (uses Windows DPAPI via the Wine prefix).
//
// Mirrors the logic in min-ed-launcher's src/MinEdLauncher/Cobra.fs:
//   - getSalt: reflect the static non-public `salt` byte[] from
//     ClientSupport.DecoderRing (inside ClientSupport.dll, shipped with ED).
//   - encrypt: ProtectedData.Protect(UTF-16LE(password), salt, CurrentUser)
//              then Convert.ToBase64String
// The resulting file is two lines:
//   line 1: username (plaintext)
//   line 2: base64(DPAPI(utf16le(password)))
// The launcher's Cobra.readCredentials accepts this as a 2-line file.
using System;
using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;

class Program
{
    static int Main(string[] args)
    {
        if (args.Length != 4)
        {
            Console.Error.WriteLine(
                "usage: MelCredHelper <ClientSupport.dll> <output.cred> <username> <password>");
            return 64;
        }

        string clientSupportDll = args[0];
        string credOutPath = args[1];
        string username = args[2];
        string password = args[3];

        byte[] salt;
        try
        {
            // The decoder ring's salt field is inside ClientSupport.dll. ED may
            // rotate this in future patches; when that happens the helper just
            // needs a rerun against the new dll.
            var asm = Assembly.LoadFrom(clientSupportDll);
            var decoderRing = asm.GetType("ClientSupport.DecoderRing");
            if (decoderRing == null)
            {
                Console.Error.WriteLine("error: type ClientSupport.DecoderRing not found in dll");
                return 2;
            }
            var saltField = decoderRing.GetField("salt",
                BindingFlags.Static | BindingFlags.NonPublic);
            if (saltField == null)
            {
                Console.Error.WriteLine("error: static non-public 'salt' field not found on DecoderRing");
                return 2;
            }
            salt = (byte[])saltField.GetValue(null);
        }
        catch (Exception e)
        {
            Console.Error.WriteLine($"error: failed to extract salt: {e.Message}");
            return 2;
        }

        byte[] plaintext = Encoding.Unicode.GetBytes(password);
        byte[] ciphertext;
        try
        {
            ciphertext = ProtectedData.Protect(plaintext, salt, DataProtectionScope.CurrentUser);
        }
        catch (Exception e)
        {
            Console.Error.WriteLine($"error: DPAPI Protect failed: {e.Message}");
            return 3;
        }

        string encoded = Convert.ToBase64String(ciphertext);
        // min-ed-launcher writes with Environment.NewLine. Under Wine .NET,
        // that's \r\n, which FileIO.readAllLines handles fine either way.
        string contents = $"{username}{Environment.NewLine}{encoded}";
        File.WriteAllText(credOutPath, contents);

        Console.Out.WriteLine($"ok: wrote {credOutPath}");
        return 0;
    }
}
