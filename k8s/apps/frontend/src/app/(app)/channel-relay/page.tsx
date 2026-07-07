'use client';

import type { JSX } from 'react';
import { useEffect } from 'react';
import { useSearchParams } from 'next/navigation';

export default function ChannelRelayPage(): JSX.Element | null {
  const searchParams = useSearchParams();

  useEffect(() => {
    const redirect = searchParams.get('redirect');

    const hash = window.location.hash.slice(1);
    const hashParams = new URLSearchParams(hash);
    const auth = hashParams.get('auth');
    const showorg = hashParams.get('showorg');
    const impersonate = hashParams.get('impersonate');

    if (!redirect || !auth) return;

    window.sessionStorage.setItem('auth', auth);
    if (showorg) window.sessionStorage.setItem('showorg', showorg);
    if (impersonate) window.sessionStorage.setItem('impersonate', impersonate);
    window.sessionStorage.setItem('channel_popup_mode', 'true');

    window.location.href = redirect;
  }, []);

  return null;
}
