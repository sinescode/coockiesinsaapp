import base64
import hashlib
from Crypto.Cipher import AES

# --- Config (mirrors your Dart SecureVault) ---
PASSWORD = "t4jTdJHA221"
SALT = "SKYSYS_PRO_SALT_99821_Bokachondro985"
PACKED_DATA = "TmdMb0xMR3JBdG95UHBBSm8vaElQdz09OmVUMHV3K1Uzc0JabHRrcktsMjFKUml6bEhGU25CSkJrVkNUVnpITEhjSDlIdUNmR3g3RTJnUjNIQXp0d042T2hVK0UyNHF3UFd1b1RrMk04c1RHL2hYSnJtaGwxNzNCS01QWVpUcmw3WVA3TE1CVGxTQS93V1E9PQ=="

def pbkdf2(password: str, salt: str, iterations: int, key_len: int) -> bytes:
    return hashlib.pbkdf2_hmac(
        'sha256',
        password.encode('utf-8'),
        salt.encode('utf-8'),
        iterations,
        dklen=key_len
    )

def unpack(packed_data: str, password: str) -> str:
    # Step 1: Base64 decode the outer wrapper
    decoded_combined = base64.b64decode(packed_data).decode('utf-8')
    
    # Step 2: Split IV and ciphertext
    parts = decoded_combined.split(':')
    if len(parts) != 2:
        raise ValueError("Invalid format")
    
    iv = base64.b64decode(parts[0])
    ciphertext = base64.b64decode(parts[1])
    
    # Step 3: Derive key using PBKDF2-HMAC-SHA256
    key = pbkdf2(password, SALT, 2000, 32)
    
    # Step 4: Decrypt using AES-GCM
    # GCM appends a 16-byte tag at the end of the ciphertext
    tag = ciphertext[-16:]
    ciphertext = ciphertext[:-16]
    
    cipher = AES.new(key, AES.MODE_GCM, nonce=iv)
    plaintext = cipher.decrypt_and_verify(ciphertext, tag)
    
    return plaintext.decode('utf-8')

if __name__ == "__main__":
    result = unpack(PACKED_DATA, PASSWORD)
    print("Decrypted:", result)
