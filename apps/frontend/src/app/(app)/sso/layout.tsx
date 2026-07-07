import { ReactNode } from 'react';

export default function SsoLayout({ children }: { children: ReactNode }) {
  return (
    <div className="light min-h-screen bg-white flex items-center justify-center">
      {children}
    </div>
  );
}
