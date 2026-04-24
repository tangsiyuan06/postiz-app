export interface Params {
  baseUrl: string;
  beforeRequest?: (url: string, options: RequestInit) => Promise<RequestInit>;
  afterRequest?: (
    url: string,
    options: RequestInit,
    response: Response
  ) => Promise<boolean>;
}
export const customFetch = (
  params: Params,
  auth?: string,
  showorg?: string
) => {
  return async function newFetch(url: string, options: RequestInit = {}) {
    const loggedAuth =
      typeof window === 'undefined'
        ? undefined
        : new URL(window.location.href).searchParams.get('loggedAuth');
    const newRequestObject = await params?.beforeRequest?.(url, options);
    const sessionAuth =
      typeof window === 'undefined'
        ? null
        : window.sessionStorage.getItem('auth');

    const sessionOrg =
      typeof window === 'undefined'
        ? null
        : window.sessionStorage.getItem('showorg');

    const sessionImpersonate =
      typeof window === 'undefined'
        ? null
        : window.sessionStorage.getItem('impersonate');

    const fetchRequest = await fetch(params.baseUrl + url, {
      ...(newRequestObject || options),
      headers: {
        ...(showorg
          ? { showorg }
          : sessionOrg
          ? { showorg: sessionOrg }
          : {}),
        ...(options.body instanceof FormData
          ? {}
          : { 'Content-Type': 'application/json' }),
        Accept: 'application/json',
        ...(loggedAuth ? { auth: loggedAuth } : {}),
        ...options?.headers,
        ...(auth
          ? { auth }
          : sessionAuth
          ? { auth: sessionAuth }
          : {}),
        ...(sessionImpersonate
          ? { impersonate: sessionImpersonate }
          : {}),
      },
      // @ts-ignore
      ...(!options.next && options.cache !== 'force-cache'
        ? { cache: options.cache || 'no-store' }
        : {}),
    });

    if (
      !params?.afterRequest ||
      (await params?.afterRequest?.(url, options, fetchRequest))
    ) {
      return fetchRequest;
    }

    // @ts-ignore
    return new Promise((res) => {}) as Response;
  };
};

export const fetchBackend = customFetch({
  get baseUrl() {
    return process.env.BACKEND_URL!;
  },
});
