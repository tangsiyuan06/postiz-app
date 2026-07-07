import { redirect } from 'next/navigation';

export default function SsoRedirectPage({
  searchParams,
}: {
  searchParams: { [key: string]: string | string[] | undefined };
}) {
  const token =
    typeof searchParams.token === 'string' ? searchParams.token : undefined;

  redirect(
    token
      ? `/sso?auth_code=${encodeURIComponent(token)}`
      : '/sso'
  );
}
