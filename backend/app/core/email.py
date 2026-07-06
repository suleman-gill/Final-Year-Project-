import logging
import resend
from app.core.config import settings

logger = logging.getLogger("uvicorn")

def send_otp_email(to_email: str, otp: str, expires_minutes: int):
    """Send an OTP email via Resend."""
    if not settings.RESEND_API_KEY:
        logger.warning(f"RESEND_API_KEY is not set. Would have sent OTP {otp} to {to_email}")
        return

    try:
        resend.api_key = settings.RESEND_API_KEY
        
        html_content = f"""
        <div style="font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; max-width: 600px; margin: 0 auto; background-color: #F8FAFC; padding: 40px 20px; border-radius: 10px;">
            <div style="text-align: center; margin-bottom: 30px;">
                <h1 style="color: #0F172A; margin: 0; font-size: 28px;">Tilawah AI</h1>
                <p style="color: #10B981; margin: 5px 0 0; font-size: 16px; font-weight: bold;">Password Reset</p>
            </div>
            
            <div style="background-color: #FFFFFF; padding: 30px; border-radius: 8px; box-shadow: 0 4px 6px rgba(0,0,0,0.05);">
                <p style="color: #64748B; font-size: 16px; line-height: 1.5; margin-top: 0;">Salam,</p>
                <p style="color: #64748B; font-size: 16px; line-height: 1.5;">We received a request to reset your password. Please use the verification code below. This code will expire in <strong>{expires_minutes} minutes</strong>.</p>
                
                <div style="text-align: center; margin: 30px 0;">
                    <div style="display: inline-block; background-color: #F8FAFC; border: 2px dashed #10B981; border-radius: 8px; padding: 15px 30px; font-size: 32px; font-weight: bold; color: #0F172A; letter-spacing: 5px;">
                        {otp}
                    </div>
                </div>
                
                <p style="color: #64748B; font-size: 14px; line-height: 1.5;">If you did not request a password reset, you can safely ignore this email.</p>
            </div>
            
            <div style="text-align: center; margin-top: 30px;">
                <p style="color: #94A3B8; font-size: 12px; margin: 0;">&copy; {settings.ENVIRONMENT.capitalize()} Tilawah AI. All rights reserved.</p>
            </div>
        </div>
        """
        
        response = resend.Emails.send({
            "from": settings.FROM_EMAIL,
            "to": to_email,
            "subject": "Your Tilawah AI Verification Code",
            "html": html_content
        })
        logger.info(f"Successfully sent OTP email to {to_email}. Resend ID: {response.get('id')}")
    except Exception as e:
        logger.error(f"Failed to send OTP email to {to_email}: {e}")
