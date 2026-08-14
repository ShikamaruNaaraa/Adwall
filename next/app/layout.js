export const metadata = {
  title: "Node.js Uptime Test",
  description: "Testing Next.js on Hostinger"
};

export default function RootLayout({ children }) {
  return (
    <html lang="en">
      <body style={{ margin: 0 }}>
        {children}
      </body>
    </html>
  );
}