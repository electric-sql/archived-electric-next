import { Outlet } from "react-router-dom"
import { ShapesProvider } from "../../../../react-hooks"

export default function Root() {
  return (
    <>
      <ShapesProvider>
        <Outlet />
      </ShapesProvider>
    </>
  )
}
