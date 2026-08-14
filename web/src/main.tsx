import React from 'react';
import ReactDOM from 'react-dom/client';
import {WagmiProvider} from 'wagmi';
import {QueryClient, QueryClientProvider} from '@tanstack/react-query';
import {BrowserRouter, Routes, Route, Navigate} from 'react-router-dom';
import {wagmiConfig} from './config';
import App from './App';
import Landing from './site/Landing';
import './index.css';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      // No global `refetchInterval`. It used to sit here at 15s, which meant the marketing pages
      // polled an RPC endpoint forever for data they never render. Liveness is now opted into by
      // the hooks that genuinely need it — see `useIngestedEvents` and `useScoreHistory`.
      staleTime: 15_000,
      retry: 2,
    },
  },
});

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <BrowserRouter>
          <Routes>
            <Route path="/" element={<Landing />} />
            {/* The dapp keeps its own internal tabs; only its mount point moved. */}
            <Route path="/app" element={<App />} />
            <Route path="/app/*" element={<App />} />
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
        </BrowserRouter>
      </QueryClientProvider>
    </WagmiProvider>
  </React.StrictMode>,
);
