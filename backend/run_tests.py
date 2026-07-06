import os
import sys

# Ensure backend folder is in path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from app.core.security import get_password_hash, verify_password

def run_security_tests():
    print("Running password security assertions...")
    password = "secure_password_987"
    hashed = get_password_hash(password)
    assert hashed != password
    assert verify_password(password, hashed) is True
    assert verify_password("wrong_password", hashed) is False
    print("Security assertions passed!")

def run_app_integrity_checks():
    print("Verifying core module imports...")
    from app.main import app
    from app.core.database import Base
    from app.models.user import User
    from app.models.session import RecitationSession, WordResult
    from app.websocket.recitation_ws import RecitationInferenceEngine, TilawahModelEngine, FallbackCalculatedEngine, get_engine
    
    assert app is not None
    assert Base is not None
    assert User is not None
    assert RecitationSession is not None
    assert WordResult is not None
    assert issubclass(TilawahModelEngine, RecitationInferenceEngine)
    assert issubclass(FallbackCalculatedEngine, RecitationInferenceEngine)
    print("Module integrity checks passed!")

if __name__ == "__main__":
    try:
        run_security_tests()
        run_app_integrity_checks()
        print("\nAll native backend checks passed successfully!")
    except AssertionError as e:
        print(f"Assertion failed: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Check failed with error: {e}")
        sys.exit(1)
