import { Injectable } from '@nestjs/common';

export interface SsoUserInfo {
  merchantId: string;
  merchantName: string;
}

@Injectable()
export class SsoService {
  async verifyToken(token: string): Promise<SsoUserInfo> {
    const ssoServerUrl = process.env.SSO_SERVER_URL;

    if (!ssoServerUrl) {
      throw new Error('SSO not configured: SSO_SERVER_URL is missing');
    }

    const res = await fetch(ssoServerUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ auth_code: token }),
    });

    if (!res.ok) {
      throw new Error('Invalid or expired SSO token');
    }

    const data = await res.json();

    if (!data.merchant_id || !data.merchant_name) {
      throw new Error('SSO server returned incomplete user info');
    }

    return {
      merchantId: data.merchant_id,
      merchantName: data.merchant_name,
    };
  }
}
